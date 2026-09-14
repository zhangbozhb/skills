# frozen_string_literal: true

require "yaml"
require "uri"

ROOT = File.expand_path("..", __dir__)
ERRORS = []

def check(condition, message)
  ERRORS << message unless condition
end

def parse_yaml(text, path, line_offset = 0)
  errors_before = ERRORS.length
  tree = Psych.parse_stream(text)
  check(tree.children.length == 1, "#{path}: expected one YAML document")
  pending = [tree]
  until pending.empty?
    node = pending.pop
    if node.is_a?(Psych::Nodes::Mapping)
      keys = {}
      node.children.each_slice(2) do |key, _value|
        unless key.is_a?(Psych::Nodes::Scalar)
          check(false, "#{path}: unsupported complex YAML key")
          next
        end
        check(!keys.key?(key.value),
              "#{path}:#{key.start_line + line_offset + 1}: duplicate YAML key")
        keys[key.value] = true
      end
    end
    pending.concat(node.children || [])
  end
  return nil unless ERRORS.length == errors_before

  YAML.safe_load(text, aliases: false)
rescue Psych::Exception
  ERRORS << "#{path}: invalid or unsafe YAML"
  nil
end

def load_yaml(path)
  parse_yaml(File.read(path), path)
end

def present_string?(value)
  value.is_a?(String) && !value.strip.empty?
end

# This repository uses inline Markdown links and backtick/tilde fences.
# Ignore templates inside fences; they are not existing file dependencies.
def prose(text)
  fence = nil
  text.lines.each_with_index.map do |line, index|
    marker = line.match(/^\s{0,3}(`{3,}|~{3,})/)
    if marker
      if fence.nil?
        fence = marker[1]
      elsif marker[1][0] == fence[0] && marker[1].length >= fence.length
        fence = nil
      end
      next
    end
    [line, index + 1] unless fence
  end.compact
end

def anchors(text)
  counts = Hash.new(0)
  prose(text).map do |line, _|
    heading = line.match(/^ {0,3}\#{1,6}\s+(.+?)\s*#*\s*$/)
    next unless heading

    slug = heading[1].downcase.gsub(/[^\p{L}\p{M}\p{N}_ -]/, "").tr(" ", "-")
    count = counts[slug]
    counts[slug] += 1
    count.zero? ? slug : "#{slug}-#{count}"
  end.compact
end

skill_files = Dir.glob(File.join(ROOT, "skills", "*", "SKILL.md")).sort
names = skill_files.map { |path| File.basename(File.dirname(path)) }
check(!names.empty?, "No skills found")
yaml_files = Dir.glob(File.join(ROOT, "skills", "**", "*.yaml"))
yaml_data = yaml_files.to_h { |path| [path, load_yaml(path)] }

skill_files.each do |path|
  text = File.read(path)
  match = text.match(/\A---\r?\n(.*?)^---[ \t]*\r?\n/m)
  check(!match.nil?, "#{path}: missing frontmatter")
  next unless match

  metadata = parse_yaml(match[1], path, 1)
  check(metadata.is_a?(Hash), "#{path}: frontmatter must be a mapping")
  next unless metadata.is_a?(Hash)

  name = metadata["name"]
  description = metadata["description"]
  check(metadata.keys.sort == %w[description name], "#{path}: unexpected frontmatter fields")
  check(name == File.basename(File.dirname(path)), "#{path}: name/directory mismatch")
  check(name.is_a?(String) && name.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) &&
        name.length <= 64, "#{path}: invalid name")
  check(description.is_a?(String) && !description.strip.empty?, "#{path}: missing description")
  puts "#{File.basename(File.dirname(path))}: #{text.lines.length} lines, " \
       "#{description.to_s.length} description characters"
end

catalog = yaml_data[File.join(ROOT, "skills", "catalog.yaml")]
check(catalog.is_a?(Hash) && catalog["schema_version"] == 1, "Invalid catalog version")
entries = catalog.is_a?(Hash) ? catalog.fetch("skills", []) : []
check(entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(Hash) }, "Invalid catalog skills")
entries = [] unless entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(Hash) }
check(entries.map { |entry| entry["name"] }.sort == names.sort, "Catalog/discovery mismatch")
domains = catalog.is_a?(Hash) ? catalog.fetch("domains", {}) : {}
entries.each do |entry|
  name = entry["name"]
  check(entry["path"] == "#{name}/SKILL.md", "#{name}: catalog path mismatch")
  check(domains.is_a?(Hash) && domains.key?(entry["domain"]), "#{name}: unknown domain")
  check(%w[specialist orchestrator].include?(entry["role"]), "#{name}: invalid role")
  %w[uses routes_to].each do |relation|
    targets = entry[relation]
    check(targets.is_a?(Array) && (targets - names).empty?, "#{name}: invalid #{relation} targets")
  end
end

graph = entries.to_h { |entry| [entry["name"], Array(entry["uses"])] }
visit = lambda do |name, stack|
  if stack.include?(name)
    check(false, "Cycle in catalog uses: #{(stack + [name]).join(' -> ')}")
    next
  end
  graph.fetch(name, []).each { |child| visit.call(child, stack + [name]) }
end
names.each { |name| visit.call(name, []) }

markdown_files = [File.join(ROOT, "README.md")] +
                 Dir.glob(File.join(ROOT, "skills", "**", "*.md"))
link_count = 0
markdown_files.each do |path|
  prose(File.read(path)).each do |line, number|
    line.scan(/\[[^\]]*\]\(([^)\s]+)\)/).flatten.each do |link|
      next if link.match?(/\A[a-z][a-z0-9+.-]*:/i)

      target, fragment = link.split("#", 2).map { |part| URI::DEFAULT_PARSER.unescape(part) }
      destination = target.empty? ? path : File.expand_path(target, File.dirname(path))
      check(destination.start_with?("#{ROOT}/"), "#{path}:#{number}: link leaves repository")
      next unless destination.start_with?("#{ROOT}/")

      check(File.exist?(destination), "#{path}:#{number}: missing link target")
      if fragment && !fragment.empty? && File.file?(destination) && File.extname(destination) == ".md"
        check(anchors(File.read(destination)).include?(fragment),
              "#{path}:#{number}: missing heading anchor #{fragment}")
      end
      link_count += 1
    end
  end
end

local_case_count = 0
yaml_files.select { |path| path.match?(%r{/skills/[^/]+/tests/cases\.yaml\z}) }.each do |path|
  suite = yaml_data[path]
  owner = File.basename(File.dirname(File.dirname(path)))
  check(suite.is_a?(Hash), "#{path}: invalid local scenario suite")
  next unless suite.is_a?(Hash)

  check(suite["schema_version"] == 1 && suite["skill"] == owner &&
        suite["evidence_level"] == "scenario_walkthrough", "#{path}: invalid local scenario metadata")
  items = suite["cases"]
  check(items.is_a?(Array) && !items.empty?, "#{path}: local scenario suite must not be empty")
  next unless items.is_a?(Array)

  check(items.all? { |item| item.is_a?(Hash) }, "#{path}: local scenarios must be mappings")
  next unless items.all? { |item| item.is_a?(Hash) }

  check(items.map { |item| item["id"] }.uniq.length == items.length,
        "#{path}: duplicate local scenario IDs")
  items.each_with_index do |item, index|
    location = "#{path}:case #{index + 1}"
    check(present_string?(item["id"]), "#{location}: missing local scenario ID")
    check(present_string?(item["request"]) ||
          (present_string?(item["initial_request"]) && present_string?(item["follow_up"])),
          "#{location}: missing local scenario input")
    check(item["expected"].is_a?(Hash) && !item["expected"].empty?,
          "#{location}: missing local scenario expectations")
  end
  local_case_count += items.length
end

unless ERRORS.empty?
  warn ERRORS.join("\n")
  abort "FAIL: #{ERRORS.length} structural issue(s)"
end

puts "PASS: #{names.length} skills, #{yaml_files.length} YAML files, #{link_count} local links, " \
     "#{local_case_count} local walkthrough cases."
puts "Static checks only. Scenario expectations and actual model routing require separate review."
