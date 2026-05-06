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
