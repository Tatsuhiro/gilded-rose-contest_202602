# frozen_string_literal: true

# =============================================================
# Golden Master Spec - DO NOT MODIFY
# =============================================================
# This spec verifies that the refactored code preserves the
# original behavior of GildedRose. If any of these tests fail,
# the Correctness score (20 pts) becomes 0.
# =============================================================

require File.join(File.dirname(__FILE__), "gilded_rose")

RSpec.describe GildedRose do
  def update_items(*items)
    gilded_rose = GildedRose.new(items)
    gilded_rose.update_quality
    items
  end

  # ---------------------------------------------------------
  # Normal items
  # ---------------------------------------------------------
  describe "Normal item" do
    it "decreases quality and sell_in by 1" do
      items = update_items(Item.new("Normal Item", 10, 20))
      expect(items[0].sell_in).to eq 9
      expect(items[0].quality).to eq 19
    end

    it "degrades quality twice as fast after sell date" do
      items = update_items(Item.new("Normal Item", 0, 20))
      expect(items[0].quality).to eq 18
    end

    it "never has negative quality" do
      items = update_items(Item.new("Normal Item", 5, 0))
      expect(items[0].quality).to eq 0
    end

    it "never has negative quality even after sell date" do
      items = update_items(Item.new("Normal Item", -1, 0))
      expect(items[0].quality).to eq 0
    end

    it "degrades quality by 1 when quality is 1 and past sell date" do
      items = update_items(Item.new("Normal Item", 0, 1))
      expect(items[0].quality).to eq 0
    end
  end

  # ---------------------------------------------------------
  # Aged Brie
  # ---------------------------------------------------------
  describe "Aged Brie" do
    it "increases in quality as it gets older" do
      items = update_items(Item.new("Aged Brie", 2, 0))
      expect(items[0].quality).to eq 1
    end

    it "increases in quality twice as fast after sell date" do
      items = update_items(Item.new("Aged Brie", 0, 0))
      expect(items[0].quality).to eq 2
    end

    it "never has quality above 50" do
      items = update_items(Item.new("Aged Brie", 2, 50))
      expect(items[0].quality).to eq 50
    end

    it "never exceeds 50 even after sell date" do
      items = update_items(Item.new("Aged Brie", 0, 49))
      expect(items[0].quality).to eq 50
    end

    it "decreases sell_in" do
      items = update_items(Item.new("Aged Brie", 5, 10))
      expect(items[0].sell_in).to eq 4
    end
  end

  # ---------------------------------------------------------
  # Sulfuras (legendary item)
  # ---------------------------------------------------------
  describe "Sulfuras, Hand of Ragnaros" do
    it "never changes quality" do
      items = update_items(Item.new("Sulfuras, Hand of Ragnaros", 0, 80))
      expect(items[0].quality).to eq 80
    end

    it "never changes sell_in" do
      items = update_items(Item.new("Sulfuras, Hand of Ragnaros", 0, 80))
      expect(items[0].sell_in).to eq 0
    end

    it "keeps quality at 80 regardless" do
      items = update_items(Item.new("Sulfuras, Hand of Ragnaros", -1, 80))
      expect(items[0].quality).to eq 80
    end
  end

  # ---------------------------------------------------------
  # Backstage passes
  # ---------------------------------------------------------
  describe "Backstage passes to a TAFKAL80ETC concert" do
    it "increases quality by 1 when more than 10 days" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 15, 20))
      expect(items[0].quality).to eq 21
    end

    it "increases quality by 2 when 10 days or less" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 10, 20))
      expect(items[0].quality).to eq 22
    end

    it "increases quality by 2 when 6 days" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 6, 20))
      expect(items[0].quality).to eq 22
    end

    it "increases quality by 3 when 5 days or less" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 5, 20))
      expect(items[0].quality).to eq 23
    end

    it "increases quality by 3 when 1 day" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 1, 20))
      expect(items[0].quality).to eq 23
    end

    it "drops quality to 0 after the concert" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 0, 20))
      expect(items[0].quality).to eq 0
    end

    it "never exceeds quality of 50" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 5, 49))
      expect(items[0].quality).to eq 50
    end

    it "decreases sell_in" do
      items = update_items(Item.new("Backstage passes to a TAFKAL80ETC concert", 15, 20))
      expect(items[0].sell_in).to eq 14
    end
  end

  # ---------------------------------------------------------
  # Golden Master: 30-day simulation
  # Matches the output of texttest_fixture.rb exactly
  # ---------------------------------------------------------
  describe "Golden Master (30-day simulation)" do
    GOLDEN_ITEMS = [
      ["+5 Dexterity Vest", 10, 20],
      ["Aged Brie", 2, 0],
      ["Elixir of the Mongoose", 5, 7],
      ["Sulfuras, Hand of Ragnaros", 0, 80],
      ["Sulfuras, Hand of Ragnaros", -1, 80],
      ["Backstage passes to a TAFKAL80ETC concert", 15, 20],
      ["Backstage passes to a TAFKAL80ETC concert", 10, 49],
      ["Backstage passes to a TAFKAL80ETC concert", 5, 49],
      ["Conjured Mana Cake", 3, 6],
    ].freeze

    def run_simulation(days)
      items = GOLDEN_ITEMS.map { |name, sell_in, quality| Item.new(name, sell_in, quality) }
      gr = GildedRose.new(items)
      results = []
      days.times do
        gr.update_quality
        results << items.map { |i| [i.name, i.sell_in, i.quality] }
      end
      results
    end

    it "produces consistent output over 30 days" do
      # Run simulation twice to confirm deterministic behavior
      run1 = run_simulation(30)
      run2 = run_simulation(30)
      expect(run1).to eq(run2)
    end

    it "day 1: +5 Dexterity Vest degrades normally" do
      result = run_simulation(1)
      vest = result[0].find { |name, _, _| name == "+5 Dexterity Vest" }
      expect(vest[1]).to eq 9   # sell_in
      expect(vest[2]).to eq 19  # quality
    end

    it "day 1: Aged Brie increases quality" do
      result = run_simulation(1)
      brie = result[0].find { |name, _, _| name == "Aged Brie" }
      expect(brie[1]).to eq 1
      expect(brie[2]).to eq 1
    end

    it "day 1: Sulfuras never changes" do
      result = run_simulation(1)
      sulfuras = result[0].select { |name, _, _| name == "Sulfuras, Hand of Ragnaros" }
      expect(sulfuras[0][1]).to eq 0
      expect(sulfuras[0][2]).to eq 80
      expect(sulfuras[1][1]).to eq(-1)
      expect(sulfuras[1][2]).to eq 80
    end
  end
end
