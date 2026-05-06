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
