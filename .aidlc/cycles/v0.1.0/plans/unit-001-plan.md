# Unit 001: リポジトリ衛生整備 — 計画

## 概要
.gitignoreを新規作成し、`__pycache__/`と`*.pyc`を除外エントリとして追加する。

## 現状確認
- `.gitignore` は存在しない（新規作成が必要）
- `git ls-files` で追跡済みの `__pycache__/` や `.pyc` は検出されなかった（`git rm --cached` は不要）

## 変更対象ファイル
- `.gitignore`（新規作成）

## 実装計画
1. `.gitignore` を新規作成（`__pycache__/`, `*.pyc` エントリ）
2. `git ls-files` で `.pyc` ファイルがリポジトリに含まれていないことを再確認
3. `make test` で全テストパスを確認

## 完了条件チェックリスト
- [ ] .gitignoreに`__pycache__/`と`*.pyc`のエントリが存在する
- [ ] リポジトリから追跡済みの`__pycache__/`と`.pyc`ファイルが除外されている
- [ ] 追跡除外後の検証完了
- [ ] `make test` が全パスすること
