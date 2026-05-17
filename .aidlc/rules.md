# jailrun プロジェクト固有 AI-DLC ルール

## ファイル管理方針

### `.aidlc/cycles/` は untrack（恒久方針）

`.aidlc/cycles/` 配下のサイクル成果物は **git 管理外**（`.gitignore` で除外）とする。

**根拠**:
- jailrun リポジトリは AI-DLC のサイクル進捗ファイルを履歴として残さない方針
- `operations/progress.md` / `history/operations.md` 等の Operations Phase 固定スロットも tracked にしない
- 代替記録: GitHub Issue（Retrospective Issue / バックログ Issue）と PR マージコミット、`HISTORY.md`、git tag で運用を追跡

**AI エージェントへの指示**:
- `.aidlc/cycles/` を tracked 化する提案・変更は行わない
- `.aidlc/cycles/` 配下のファイルを `git add` しない
- Operations Phase の `OPERATIONS_COMPLETE` コミット対象が空でも警告で中断せず続行する
- Issue #53（AI-DLC 的リリース手順）は untrack 方針を前提に運用する（クローズ要否は別途判断）

**例外**: `.aidlc/config.toml` / `.aidlc/rules.md` / `.aidlc/operations.md` 等の `.aidlc/` 直下ファイルは tracked 対象（`.gitignore` パターンは `.aidlc/cycles/` のみ）。

## 振り返り（Retrospective）の進め方

### 対話必須ルール【絶対遵守】

Operations Phase の振り返り（`steps/operations/04-completion.md` §1）を実施する際は、AI エージェントが KPT / Try / Problem を独断で生成して `gh issue create` してはならない。**必ずユーザーとの対話を経て、AskUserQuestion で項目ごとに要否・内容・mirror 送信可否を確認する**こと。

**根拠**: v0.3.4 Operations Phase で AI エージェントが対話なしに振り返り Issue #70 を作成した運用ミス（同 Issue 問題 6 参照）への再発防止。

**手順（最低限）**:

1. KPT 案 / Problem 候補 / Try 候補を提示する前に、ユーザーに「振り返りを実施するか」を AskUserQuestion で確認（`feedback_mode=disabled` 以外の場合）
2. 各 Problem について以下を 1 項目ずつ AskUserQuestion で対話確認:
   - 内容に過不足ないか
   - 主因切り分け（プロダクト固有 / AI-DLC Starter Kit 固有 / 両方に責任）
   - mirror 送信（AI-DLC feedback 起票）の可否（送信する / しない / 保留）
3. 関連 Issue が既に存在する場合は、振り返り Issue 本文に重複記載せず、既存 Issue へのコメント統合を提案する（v0.3.4 で #66 へ Self-Healing 経緯を統合した形式）
4. 全項目確定後に `gh issue create` または `gh api PATCH` で本文反映

**禁止事項**:

- AskUserQuestion を経ずに振り返り Issue を新規作成すること
- AskUserQuestion を経ずに既存振り返り Issue の本文を一括書き換えすること
- 「auto mode 中だから対話を省く」判断（auto mode は低リスク・反復作業向けで、振り返りのような判断要件には適用されない）

**例外**: `feedback_mode=disabled` の場合のみ §1 全体をスキップ。`silent` / `mirror` のいずれでも上記対話必須ルールが適用される。

## Unit 分割ガイドライン

### 背景: v0.4.3 サイクルでの教訓

v0.4.3 サイクルの retrospective で、Unit 001 (`proxy-bind-race-mitigation`) にレビュー負荷が集中する事象が確認された（レビュー 9 round / 指摘 14 件 / defer 起票 2 件、他 2 Unit はそれぞれ 8R-11 件 / 4R-1 件で defer なし）。Unit 001 は「NFR latency 検証 (+15ms ≤ +50ms)」「race condition 検証」「並列 bats テスト戦略」の 3 検証次元を 1 Unit に内包しており、これが指摘集中と defer 起票の主因と整理された（#97）。

本ガイドラインは、Inception Phase で AI エージェントが Unit を定義する際の判断指針として、検証次元集中を抑制する基準を提供する。

### 3 つの検証次元

Unit 内に含まれる「検証作業の種類」を 3 つの直交する次元として定義する。同一 Unit 内で 2 つ以上が該当する場合は分割を検討する（次節「分割判定ルール」）。

#### NFR 検証

- **判定基準**: 性能（latency / throughput）/ リソース消費（memory / fd / 接続数）/ 信頼性（failover / retry 挙動）のいずれかについて、測定値・上限値・閾値判定を含む検証作業を伴う
- **具体例**:
  - v0.4.3 Unit 001: proxy 経由 connect の latency overhead を `+15ms ≤ +50ms` で測定
  - 新規 API エンドポイントの p95 応答時間を 200ms 以下で測定
- **非該当例**: 純粋なロジック修正（path 解決規則の追加等）で測定値判定を伴わない場合

#### 並行性検証

- **判定基準**: race condition / lock / 順序保証のいずれかについて、競合状態を意図的に再現または防止する検証作業を伴う
- **具体例**:
  - v0.4.3 Unit 001: `bind_in_range` の同時 bind 競合を再現し retry でリカバリすることを検証
  - 共有キャッシュ更新時の lost update 防止検証
- **非該当例**: 読み取り専用関数の追加で複数スレッド／プロセスからの呼び出しが想定されない場合

#### テスト基盤

- **判定基準**: 新規 test runner 導入 / 並列実行戦略の導入・変更 / 新規 fixture や CI matrix の導入を伴う
- **具体例**:
  - v0.4.3 Unit 001: bats を並列実行する戦略の新規導入と固定化
  - 新規 docker fixture（疑似 SMTP サーバ等）の追加
- **非該当例**: 既存テストフレームワーク内に通常のテストケースを追加するだけの場合

### 分割判定ルール

候補 Unit 内に該当する検証次元の数で以下のアクションを取ることを推奨する（should レベル）。

| 該当次元数 | 推奨アクション |
|-----------|---------------|
| 0 | そのまま単一 Unit で実施可（純粋な実装変更 / docs only 等） |
| 1 | そのまま単一 Unit で実施可（推奨） |
| 2 以上 | **分割を検討**（次元ごとに Unit を分離するか、可能な部分実装を別 Unit に切り出す） |

「2 以上」で必ず分割すべきわけではなく、**検討** が必須である。分割困難と判断する場合は次節「例外ルート」に従って例外理由を明文化する。

### 例外ルート（分割困難時の運用）

#### 適用条件

例外ルートは次のいずれかに該当する場合のみ適用する。

- **B-1a**: 検証対象が共通の状態を共有し、検証次元を分離すると検証自体が成立しない場合（例: 同一プロセス内の lock + latency を同時に観測する必要がある）
- **B-1b**: 検証次元間に技術的依存（順序性 / 不可分性）があり、分離すると意味的に等価でない場合

該当しない場合は分割するのが原則。

#### 記載先と書式

例外を適用する場合、以下の判断基準で記載先を選び、書式テンプレートに従って明文化する。

- **記載先の選択**:
  - 複数の Unit に共通する例外理由（プロジェクト横断の制約） → `requirements/intent.md` の「制約事項」配下
  - 単一の Unit 固有の例外理由 → 当該 Unit 定義ファイル（`story-artifacts/units/{NNN}-{slug}.md`）の「技術的考慮事項」配下
- **書式テンプレート**:

  ```markdown
  ### Unit 分割例外: <Unit 名 or サブテーマ>

  - **例外理由**: <B-1a / B-1b のどちらか、および具体的な技術的依存内容>
  - **含まれる検証次元**: <NFR 検証 / 並行性検証 / テスト基盤 のうち該当するものを列挙>
  - **事後追跡 Issue**: #<番号>（任意、起票済みの場合）
  ```

#### 事後追跡義務

- 例外を 2 サイクル連続で使用した場合、設計の見直し（共通基盤化 / 検証次元の再定義）を Operations Phase の振り返りで議題化する
- 検出方法: 直近 2 つのリリース済みサイクル（`cycle/*` ブランチ）の `requirements/intent.md` と `story-artifacts/units/*.md` を走査し、上記書式に合致するブロックが両サイクルに存在するかで判定する（カウント単位はサイクル単位、Unit 単位ではない）

#### 他 defer ルートとの区別

本ガイドラインの「例外ルート」は **Inception Phase（Unit 定義時）の判断** として作用する。Construction Phase レビュー時の `OUT_OF_SCOPE` / `TECHNICAL_BLOCKER` 判定や `type:defer-from-review` Issue 起票（`steps/common/review-flow.md`）とは別ルートであり、混同しないこと。両者は適用フェーズ・対象（Unit 構造 vs レビュー指摘）が異なる。

### 他ルールとの整合

#### 適用フェーズの限定

本ガイドラインの規則本体（分割判定 / 例外承認）の発動は Inception Phase の Unit 定義時のみとする。Operations Phase は事後追跡義務に基づく「監視参照」（`ExceptionRecord` の 2 サイクル連続使用検出と議題化）であり、新たな分割判断・例外承認は行わない。Construction Phase では本ガイドラインの規則は参照しない。

#### 既存 2 セクションとの分離

本セクションは既存の 2 セクションと適用フェーズ・対象成果物が直交しており、優先順位の競合は想定されない。

| 既存セクション | 扱う対象 | 本ガイドラインとの関係 |
|--------------|---------|---------------------|
| `## ファイル管理方針` | `.aidlc/cycles/` の git tracked / untracked 境界 | 直交（本ガイドラインは Unit 定義の論理構造のみ扱う） |
| `## 振り返り（Retrospective）の進め方` | Operations Phase 振り返りの対話必須性 | 直交（本ガイドラインは Inception Phase に作用） |

#### 想定衝突ケースの予防

現時点で具体的な衝突シナリオは確認されていない。万一衝突が生じた場合は、適用フェーズが先に作用するルールを優先する（本ガイドラインは Inception、振り返りは Operations の関係）。

### 関連リンク

- Issue #97: Unit 分割ガイドライン: 検証次元（NFR / 並行性 / テスト基盤）の同時集中を避ける（本ガイドライン策定の直接根拠）
- v0.4.3 retrospective 文脈: 上記「背景」節参照。独立した `Retrospective: v0.4.3` Issue は存在しないため、本サイクルでは Issue #97 を retrospective 根拠の正規参照先とする（参照: `.aidlc/cycles/v0.4.4/inception/decisions.md` DR-001。具体的な defer 起票 Issue は #94 / #95）
