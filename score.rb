#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================
# GildedRose Refactoring Contest - Auto Scoring Script
# =============================================================
#
# Usage:
#   docker compose run score            # スコア表示
#   docker compose run score-json       # JSON出力
#   docker compose run baseline         # ベースライン計測
#   docker compose run test             # テストだけ実行
#   docker compose run lint             # RuboCopだけ実行
#
# Scoring Breakdown (100 points):
#   A. Code Quality    : 40 pts (RuboCop 15, Flog 15, Flay 10)
#   B. Tests           : 30 pts (Passing 10, Coverage 10, Richness 10)
#   C. Correctness     : 20 pts (Original specs must pass - gate condition)
#   D. AI Agent Usage  : 10 pts (CLAUDE.md / rules / git log analysis)
# =============================================================

require "json"
require "open3"
require "fileutils"
require "time"

class RefactoringScorer
  TOTAL_POINTS = 100

  # --- Baseline values (GildedRose original, pre-refactoring) ---
  # Run `docker compose run baseline` to recalculate
  BASELINE = {
    rubocop_offenses: 37,
    flog_total: 104.4,
    flay_total: 96,
  }.freeze

  TARGET = {
    rubocop_offenses: 0,
    flog_total: 30.0,
    flay_total: 0,
    coverage_pct: 100.0,
    test_count_good: 20,
  }.freeze

  # コード品質スキャン対象（フラット構成・lib/構成の両方に対応）
  SCAN_PATHS = %w[lib/ src/].freeze
  # スキャン除外対象（specファイル、スコアリング、テストフィクスチャ等）
  SCAN_EXCLUDES = %w[
    score.rb
    texttest_fixture.rb
    Gemfile
    Rakefile
  ].freeze
  SCAN_EXCLUDE_PATTERNS = %w[_spec.rb _test.rb].freeze

  def initialize(project_dir: ".", json_output: false, baseline_mode: false)
    @project_dir = File.expand_path(project_dir)
    @json_output = json_output
    @baseline_mode = baseline_mode
    @scores = {}
    @details = {}
  end

  def run
    Dir.chdir(@project_dir) do
      if @baseline_mode
        run_baseline
      else
        run_scoring
      end
    end
  end

  private

  # -------------------------------------------------------
  # Utility: find scan targets
  # -------------------------------------------------------

  def scan_target
    # lib/ or src/ があればそちらを優先
    existing = SCAN_PATHS.select { |p| Dir.exist?(p) }
    return existing.join(" ") if existing.any?

    # フラット構成: .rb ファイルから非対象を除外
    rb_files = Dir.glob("*.rb").reject do |f|
      SCAN_EXCLUDES.include?(f) ||
        SCAN_EXCLUDE_PATTERNS.any? { |pat| f.end_with?(pat) }
    end
    rb_files.empty? ? "." : rb_files.join(" ")
  end

  # -------------------------------------------------------
  # A. Code Quality (40 pts)
  # -------------------------------------------------------

  def score_rubocop
    target = scan_target
    stdout, _, _ = Open3.capture3("rubocop --format json --force-exclusion #{target} 2>/dev/null")

    offense_count = begin
      result = JSON.parse(stdout)
      result.dig("summary", "offense_count").to_i
    rescue StandardError
      # Fallback to text parsing
      text_out, _, _ = Open3.capture3("rubocop #{target} 2>/dev/null")
      match = text_out.match(/(\d+)\s+offense/)
      match ? match[1].to_i : BASELINE[:rubocop_offenses]
    end

    @details[:rubocop_offenses] = offense_count
    return if @baseline_mode

    baseline = [BASELINE[:rubocop_offenses], 1].max
    improvement = [(baseline - offense_count).to_f / baseline, 0.0].max
    @scores[:rubocop] = [improvement * 15.0, 15.0].min.round(1)
  end

  def score_flog
    target = scan_target
    stdout, _, _ = Open3.capture3("flog -s #{target} 2>/dev/null")
    match = stdout.match(/([\d.]+):\s+flog total/)
    flog_total = match ? match[1].to_f : BASELINE[:flog_total]

    @details[:flog_total] = flog_total
    return if @baseline_mode

    baseline = BASELINE[:flog_total]
    target_val = TARGET[:flog_total]

    @scores[:flog] = if flog_total <= target_val
                       15.0
                     elsif flog_total >= baseline
                       0.0
                     else
                       [((baseline - flog_total) / (baseline - target_val) * 15.0), 15.0].min.round(1)
                     end
  end

  def score_flay
    target = scan_target
    stdout, _, _ = Open3.capture3("flay #{target} 2>/dev/null")
    match = stdout.match(/Total score.*?=\s*(\d+)/)
    flay_total = match ? match[1].to_i : 0

    @details[:flay_total] = flay_total
    return if @baseline_mode

    @scores[:flay] = if flay_total == 0
                       10.0
                     elsif flay_total >= 100
                       0.0
                     else
                       ((100 - flay_total) / 100.0 * 10.0).round(1)
                     end
  end

  # -------------------------------------------------------
  # B. Tests (30 pts)
  # -------------------------------------------------------

  def score_tests
    spec_files = Dir.glob("spec/**/*_spec.rb") +
                 Dir.glob("test/**/*_test.rb") +
                 Dir.glob("*_spec.rb")  # フラット構成対応
    team_specs = spec_files.reject { |f| f.include?("golden") || f.include?("original") }

    @details[:has_tests] = !team_specs.empty?
    @details[:spec_files] = team_specs

    unless team_specs.any?
      @scores[:test_existence] = 0.0
      @scores[:test_coverage] = 0.0
      @scores[:test_count] = 0.0
      @details[:test_count] = 0
      @details[:coverage_pct] = 0.0
      @details[:tests_all_passed] = false
      return
    end

    # Run rspec with SimpleCov injection (without modifying project files)
    env = { "CONTEST_COVERAGE" => "1" }
    rspec_cmd = <<~SH
      ruby -e "
        require 'simplecov'
        SimpleCov.start do
          add_filter '/spec/'
          add_filter '/test/'
          add_filter 'score.rb'
        end
        " -r rspec/autorun 2>/dev/null || true
    SH

    # Simpler approach: run rspec directly with coverage via env var
    stdout, stderr, status = Open3.capture3(
      env,
      "ruby", "-r", "simplecov", "-e",
      <<~RUBY
        SimpleCov.start do
          add_filter '/spec/'
          add_filter '/test/'
          add_filter 'score.rb'
          enable_coverage :branch
        end
        require 'rspec/autorun'
        RSpec.configure { |c| c.formatter = :json }
      RUBY
    )

    # Parse rspec JSON output
    rspec_result = begin
      JSON.parse(stdout)
    rescue StandardError
      nil
    end

    if rspec_result
      test_count = rspec_result.dig("summary", "example_count").to_i
      failure_count = rspec_result.dig("summary", "failure_count").to_i
      all_passed = failure_count == 0
    else
      # Fallback: run normally
      stdout2, _, status2 = Open3.capture3(env, "bundle", "exec", "rspec", "--format", "json")
      rspec_result = begin
        JSON.parse(stdout2)
      rescue StandardError
        nil
      end
      test_count = rspec_result&.dig("summary", "example_count").to_i
      failure_count = rspec_result&.dig("summary", "failure_count").to_i
      all_passed = failure_count == 0
    end

    @details[:test_count] = test_count
    @details[:tests_all_passed] = all_passed

    # Test existence & passing (10 pts)
    @scores[:test_existence] = if all_passed && test_count > 0
                                 10.0
                               elsif test_count > 0
                                 3.0 # tests exist but some fail
                               else
                                 0.0
                               end

    # Coverage (10 pts)
    coverage_pct = read_coverage
    @details[:coverage_pct] = coverage_pct
    @scores[:test_coverage] = [(coverage_pct / 100.0 * 10.0), 10.0].min.round(1)

    # Test richness (10 pts)
    target_count = TARGET[:test_count_good]
    @scores[:test_count] = [(test_count.to_f / target_count * 10.0), 10.0].min.round(1)
  end

  def read_coverage
    coverage_file = "coverage/.last_run.json"
    return 0.0 unless File.exist?(coverage_file)

    data = JSON.parse(File.read(coverage_file))
    data.dig("result", "line")&.to_f || 0.0
  rescue StandardError
    0.0
  end

  # -------------------------------------------------------
  # C. Correctness (20 pts) — Gate condition
  # -------------------------------------------------------

  def score_correctness
    original_spec = find_original_spec
    unless original_spec
      @details[:correctness] = "⚠ original spec not found"
      @scores[:correctness] = 0.0
      return
    end

    _, _, status = Open3.capture3("bundle", "exec", "rspec", original_spec, "--format", "progress")
    passed = status.success?

    @details[:correctness] = passed ? "PASS ✓" : "FAIL ✗"
    @scores[:correctness] = passed ? 20.0 : 0.0
  end

  def find_original_spec
    # golden_master_spec.rb を最優先（ゲート条件用）
    # オリジナルの gilded_rose_spec.rb は "fixme" テストなので除外
    candidates = %w[
      golden_master_spec.rb
      spec/golden_master_spec.rb
      spec/original_spec.rb
    ]
    candidates.find { |f| File.exist?(f) }
  end

  # -------------------------------------------------------
  # D. AI Agent Usage (10 pts)
  # -------------------------------------------------------

  def score_ai_usage
    points = 0.0
    ai_details = []

    # ----------------------------------------------------------
    # 1. Agent instruction file exists (4 pts)
    #    どのエージェントでも「指示ファイルを用意した」ことを公平に評価
    # ----------------------------------------------------------
    agent_instruction_files = {
      # Claude Code
      "CLAUDE.md" => "Claude Code",
      ".claude/CLAUDE.md" => "Claude Code",
      ".claude/settings.json" => "Claude Code",
      # Cursor
      ".cursorrules" => "Cursor",
      ".cursor/rules" => "Cursor",
      # GitHub Copilot
      ".github/copilot-instructions.md" => "GitHub Copilot",
      # Windsurf
      ".windsurfrules" => "Windsurf",
      # Aider
      ".aider.conf.yml" => "Aider",
      # Generic
      "AGENTS.md" => "Generic",
    }

    found_agents = {}
    agent_instruction_files.each do |path, agent|
      if File.exist?(path) || Dir.exist?(path)
        found_agents[agent] ||= []
        found_agents[agent] << path
      end
    end

    # .claude/ 配下のカスタムコマンド等も検出
    claude_extras = Dir.glob(".claude/**/*", File::FNM_DOTMATCH)
                       .reject { |f| File.directory?(f) }
                       .reject { |f| agent_instruction_files.key?(f) }
    if claude_extras.any?
      found_agents["Claude Code"] ||= []
      found_agents["Claude Code"] += claude_extras
    end

    if found_agents.any?
      points += 4.0
      found_agents.each do |agent, files|
        ai_details << "#{agent}: #{files.join(', ')}"
      end
    end

    # ----------------------------------------------------------
    # 2. Instruction file content quality (6 pts)
    #    中身が充実しているかを語数で判定（エージェント不問）
    # ----------------------------------------------------------
    instruction_candidates = %w[
      CLAUDE.md
      .claude/CLAUDE.md
      .cursorrules
      .cursor/rules
      .github/copilot-instructions.md
      .windsurfrules
      .aider.conf.yml
      AGENTS.md
    ]

    best_word_count = 0
    best_file = nil
    instruction_candidates.each do |path|
      next unless File.exist?(path) && File.file?(path)

      content = File.read(path)
      wc = content.split.length
      if wc > best_word_count
        best_word_count = wc
        best_file = path
      end
    end

    if best_file
      if best_word_count >= 80
        points += 6.0
        ai_details << "#{best_file}: #{best_word_count} words (comprehensive)"
      elsif best_word_count >= 50
        points += 4.0
        ai_details << "#{best_file}: #{best_word_count} words (substantial)"
      elsif best_word_count >= 20
        points += 2.0
        ai_details << "#{best_file}: #{best_word_count} words (basic)"
      else
        points += 1.0
        ai_details << "#{best_file}: #{best_word_count} words (minimal)"
      end
    end

    @details[:ai_usage] = ai_details
    @scores[:ai_usage] = [points, 10.0].min
  end

  # -------------------------------------------------------
  # Output
  # -------------------------------------------------------

  def run_baseline
    puts "=== Calculating Baseline Values ==="
    puts ""
    score_rubocop
    score_flog
    score_flay
    puts "  RuboCop offenses : #{@details[:rubocop_offenses]}"
    puts "  Flog total       : #{@details[:flog_total]}"
    puts "  Flay total       : #{@details[:flay_total]}"
    puts ""
    puts "Update BASELINE hash in score.rb with these values."
  end

  def run_scoring
    score_rubocop
    score_flog
    score_flay
    score_tests
    score_correctness
    score_ai_usage

    total = @scores.values.sum.round(1)

    if @json_output
      puts JSON.pretty_generate({
        total_score: total,
        max_score: TOTAL_POINTS,
        scores: @scores,
        details: @details,
        timestamp: Time.now.iso8601,
      })
    else
      print_report(total)
    end
  end

  def print_report(total)
    w = 55
    puts ""
    puts "=" * w
    puts "  🏆 GildedRose Refactoring Contest - SCORE REPORT"
    puts "=" * w

    quality_sum = cat_sum(:rubocop, :flog, :flay)
    puts ""
    puts "  📊 A. Code Quality                    #{quality_sum} / 40"
    puts "  ┌─────────────────────────────────────────────┐"
    puts "  │ RuboCop    #{bar(@scores[:rubocop], 15)}  #{fmt(@scores[:rubocop])}/15  (#{@details[:rubocop_offenses]} offenses)"
    puts "  │ Flog       #{bar(@scores[:flog], 15)}  #{fmt(@scores[:flog])}/15  (complexity: #{@details[:flog_total]})"
    puts "  │ Flay       #{bar(@scores[:flay], 10)}  #{fmt(@scores[:flay])}/10  (duplication: #{@details[:flay_total]})"
    puts "  └─────────────────────────────────────────────┘"

    test_sum = cat_sum(:test_existence, :test_coverage, :test_count)
    puts ""
    puts "  🧪 B. Tests                           #{test_sum} / 30"
    puts "  ┌─────────────────────────────────────────────┐"
    puts "  │ Passing    #{bar(@scores[:test_existence], 10)}  #{fmt(@scores[:test_existence])}/10  (#{@details[:test_count]} tests, pass: #{@details[:tests_all_passed] ? '✓' : '✗'})"
    puts "  │ Coverage   #{bar(@scores[:test_coverage], 10)}  #{fmt(@scores[:test_coverage])}/10  (#{@details[:coverage_pct]}%)"
    puts "  │ Richness   #{bar(@scores[:test_count], 10)}  #{fmt(@scores[:test_count])}/10  (#{@details[:test_count]} cases)"
    puts "  └─────────────────────────────────────────────┘"

    puts ""
    puts "  ✅ C. Correctness                     #{fmt(@scores[:correctness])} / 20"
    puts "  ┌─────────────────────────────────────────────┐"
    puts "  │ Original spec: #{@details[:correctness]}"
    puts "  │ #{@scores[:correctness] == 0 ? '⚠  GATE FAILED — behavior broken!' : '   All original behaviors preserved'}"
    puts "  └─────────────────────────────────────────────┘"

    puts ""
    puts "  🤖 D. AI Agent Usage                  #{fmt(@scores[:ai_usage])} / 10"
    puts "  ┌─────────────────────────────────────────────┐"
    (@details[:ai_usage] || []).each { |d| puts "  │ • #{d}" }
    puts "  │ (none detected)" if (@details[:ai_usage] || []).empty?
    puts "  └─────────────────────────────────────────────┘"

    puts ""
    puts "=" * w
    puts "   TOTAL SCORE:  #{total} / #{TOTAL_POINTS}    #{grade(total)}"
    puts "=" * w
    puts ""
  end

  def cat_sum(*keys)
    keys.sum { |k| @scores[k] || 0.0 }.round(1)
  end

  def fmt(val)
    format("%5.1f", val || 0.0)
  end

  def bar(val, max)
    return "          " if max == 0
    filled = ((val || 0.0) / max * 10).round
    "█" * filled + "░" * (10 - filled)
  end

  def grade(total)
    case total
    when 90..100 then "🥇 S — Amazing!"
    when 80..89  then "🥈 A — Excellent"
    when 70..79  then "🥉 B — Great"
    when 60..69  then "   C — Good"
    when 50..59  then "   D — Fair"
    else              "   E — Needs Work"
    end
  end
end

# --- Entry Point ---
if __FILE__ == $PROGRAM_NAME
  json_mode = ARGV.include?("--json")
  baseline_mode = ARGV.include?("--baseline")

  scorer = RefactoringScorer.new(
    project_dir: ".",
    json_output: json_mode,
    baseline_mode: baseline_mode,
  )
  scorer.run
end
