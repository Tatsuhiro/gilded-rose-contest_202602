# 🏆 GildedRose リファクタリングコンテスト

> リファクタリング対象のコードは [GildedRose-Refactoring-Kata](https://github.com/emilybache/GildedRose-Refactoring-Kata)（by Emily Bache）の Ruby 版をベースにしています。
> 仕様の詳細は [GildedRose Requirements](https://github.com/emilybache/GildedRose-Refactoring-Kata/blob/main/GildedRoseRequirements.md) を参照してください。

## ルール

- **人間はAIに指示するのみ** — コードを直接書くのは禁止
  - コードの記述・修正はすべてAIコーディングエージェントに任せてください
  - 人間が行えるのは、AIへのプロンプト入力・指示出しのみです
  - ターミナルでのコマンド実行（`docker compose run --rm score` 等）は人間が行ってOKです
- AIコーディングエージェント（Claude Code, Cursor, GitHub Copilot 等）を使ってリファクタリングしてください
- 制限時間: **60〜90分**（運営の指示に従ってください）

## 禁止事項 🚫

### ファイル変更の禁止
以下のファイルは変更・削除しないでください。変更した場合は失格となります。
- `golden_master_spec.rb` — 正当性チェック用ゲートspec
- `score.rb` — スコアリングスクリプト
- `Dockerfile`, `docker-compose.yml`, `Gemfile`
- `texttest_fixture.rb`

### 禁止行為
- **人間がコードを書くこと** — コードの記述・修正はすべてAIエージェント経由で行ってください。ファイル名の変更やディレクトリ作成もAIに指示してください
- **既存のGildedRose解答をコピー&ペーストすること** — GitHubなどに公開されている既存の解答を、AIを介さず直接持ち込むのは禁止です
- **`score.rb` の内容をAIに読ませてスコアをハックすること** — 「スコアが最大になるよう最適化して」のような指示は禁止です。リファクタリングとテスト充実の結果としてスコアが上がることを目指してください

### やること

1. `gilded_rose.rb` をリファクタリングする（AIエージェントに指示して実施）
2. `gilded_rose_spec.rb` にテストを追加・充実させる（AIエージェントに指示して実施）
   - `gilded_rose_spec.rb` は初期状態では "fixme" テスト1つだけのスターターファイルです
   - このファイルをAIに書き換えさせて、テストを充実させてください
   - テストの有無・カバレッジ・テストケース数がスコアに反映されます（B. テスト: 30点）
3. AIエージェントの設定ファイル（`CLAUDE.md`, `.cursorrules` 等）を整備する

## セットアップ

### 前提条件

- Docker & Docker Compose がインストール済み
- Git がインストール済み
- このリポジトリのfork

### 手順

```bash
# 1. リポジトリをclone
git clone <your-repo-url>
cd gilded-rose-contest

# 2. Dockerイメージをビルド
docker compose build

# 3. ベースライン確認（リファクタリング前のスコア）
docker compose run --rm baseline

# 4. 現在のスコアを確認
docker compose run --rm score
```

## コンテスト中のコマンド

```bash
# スコア確認（メインコマンド — pushごとに実行推奨）
docker compose run --rm score

# JSON形式で出力（集計用）
docker compose run --rm score-json

# テストだけ実行
docker compose run --rm test

# RuboCopだけ実行
docker compose run --rm lint
```

## スコアリング（100点満点）

| カテゴリ | 配点 | 計測方法 |
|---------|------|---------|
| **A. コード品質** | **40点** | |
| └ RuboCop | 15点 | offense数の削減率 |
| └ Flog (複雑度) | 15点 | メソッド複雑度スコア |
| └ Flay (重複) | 10点 | コード重複スコア |
| **B. テスト** | **30点** | |
| └ テスト全パス | 10点 | RSpec pass/fail |
| └ カバレッジ | 10点 | SimpleCov 行カバレッジ |
| └ テスト充実度 | 10点 | テストケース数 |
| **C. 正当性** | **20点** | オリジナルspecが通ること（**ゲート条件**） |
| **D. AI活用度** | **10点** | CLAUDE.md, .cursorrules 等の設定ファイルやSkills, SubAgentsの活用 |

### ⚠ 重要: ゲート条件

`spec/gilded_rose_spec.rb`（オリジナルspec）が**1つでも失敗すると正当性が0点**になります。
リファクタリングで振る舞いを壊さないよう注意してください。

## 対象ファイル

### 変更OK
- `gilded_rose.rb` — メインのリファクタリング対象
- `gilded_rose_spec.rb` — オリジナルのスターターspec（自由に書き換えてOK）
- 新規 `.rb` ファイルの追加（クラス分割等）
- `spec/` ディレクトリへのテスト追加、またはルート直下への `*_spec.rb` 追加
- `.claude/`, `CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md` 等 — AIエージェント設定

### 変更禁止 🚫
- `golden_master_spec.rb` — 正当性チェック用ゲートspec
- `score.rb` — スコアリングスクリプト
- `Dockerfile`, `docker-compose.yml`, `Gemfile`
- `texttest_fixture.rb`

## Tips

- 最初に `CLAUDE.md` や `.cursorrules` を整備すると、AIの出力品質が上がります
- こまめに `docker compose run --rm score` してスコアの推移を確認しましょう
- テストを先に書かせてからリファクタリングする戦略が有効です
- `docker compose run --rm test` でテストだけ素早く回せます
