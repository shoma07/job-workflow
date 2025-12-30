# Context から Argument への設計見直し

**作成日**: 2025年12月30日

---

## 背景と目的

### 現在の問題点

Output機能の実装により、以下の設計上の問題が明確になりました：

1. **Contextの責務が曖昧**
   - 初期引数（Job起動時のパラメータ）
   - タスク間の状態共有（中間結果の保持）
   - Output管理
   - JobStatus管理
   
2. **不要な状態の書き換え**
   - Outputで結果を受け渡せるため、contextの値を書き換える必要がない
   - しかし現在の設計では`ctx.result = ...`のような書き換えが可能

3. **シリアライゼーションの重複**
   - ActiveJobがargumentsを自動で永続化
   - さらにContextSerializerで独自に永続化している

### 新しい設計方針

**Context の責務を明確化**:
- ✅ Job全体の初期引数（イミュータブル）
- ✅ Output管理（タスクの実行結果）
- ✅ JobStatus管理（並列タスクのステータス）
- ❌ タスク間の状態共有（Outputで代替）

**DSL の改善**:
```ruby
# 現在（混乱を招く）
context :user_id, "Integer"
context :items, "Array[String]"

# 提案（明確）
argument :user_id, "Integer"
argument :items, "Array[String]"
```

**アクセス方法の改善**:
```ruby
# 現在（引数と中間状態が区別できない）
task :process do |ctx|
  user_id = ctx.user_id       # 引数
  ctx.result = "processed"    # 中間状態（非推奨だが可能）
end

# 提案（明確に区別）
task :process do |ctx|
  user_id = ctx.argument.user_id  # 引数（イミュータブル）
  # ctx.argument は読み取り専用
  # 結果は return で Output に保存
  { result: "processed" }
end
```

---

## 提案される変更

### 1. 新しいクラス構造

#### 1.1 ArgumentDef クラス（ContextDef のリネーム）

```ruby
# lib/shuttle_job/argument_def.rb
module ShuttleJob
  class ArgumentDef
    attr_reader :name     # Symbol
    attr_reader :type     # String
    attr_reader :default  # untyped
    
    def initialize(name:, type:, default:)
      @name = name
      @type = type
      @default = default
    end
  end
end
```

**変更内容**: ファイル名とクラス名のリネームのみ。ロジックは同一。

---

#### 1.2 Arguments クラス（新規作成）

```ruby
# lib/shuttle_job/arguments.rb
module ShuttleJob
  class Arguments
    attr_reader :data  # Hash[Symbol, untyped]
    
    class << self
      # Workflow定義から初期化
      def from_workflow(workflow)
        data = workflow.arguments.to_h { |arg_def| [arg_def.name, arg_def.default] }
        new(data:)
      end
    end
    
    def initialize(data:)
      @data = data.freeze  # イミュータブル
      @reader_names = data.keys.to_set
    end
    
    # Hash から復元
    def merge!(other_data)
      # イミュータブルなので merge! ではなく新しいインスタンスを返す
      merged = data.merge(other_data.slice(*@reader_names.to_a))
      self.class.new(data: merged)
    end
    
    # 動的アクセス（読み取り専用）
    def method_missing(name, *args, **kwargs, &block)
      return super unless args.empty? && kwargs.empty? && block.nil?
      return super unless @reader_names.include?(name.to_sym)
      
      data[name.to_sym]
    end
    
    def respond_to_missing?(sym, include_private)
      @reader_names.include?(sym.to_sym) || super
    end
    
    # シリアライゼーション用
    def to_h
      data
    end
    
    private
    
    attr_reader :reader_names  # Set[Symbol]
  end
end
```

**特徴**:
- ✅ イミュータブル（`freeze`）
- ✅ 読み取り専用アクセス（`method_missing`）
- ✅ 書き込みメソッドなし
- ✅ シンプルな構造

---

#### 1.3 Context クラスの簡素化

```ruby
# lib/shuttle_job/context.rb
module ShuttleJob
  class Context
    attr_reader :arguments  # Arguments（読み取り専用）
    attr_reader :output     # Output
    attr_reader :job_status # JobStatus
    
    class << self
      def from_workflow(workflow)
        new(arguments: Arguments.from_workflow(workflow))
      end
    end
    
    # 初期化
    # ArgumentsはActiveJobのargumentsとして渡されるため、
    # シリアライゼーション対象から除外
    def initialize(
      arguments:,
      each_context: {},
      task_outputs: [],
      task_job_statuses: []
    )
      @arguments = arguments.is_a?(Arguments) ? arguments : Arguments.new(data: arguments)
      @each_context = EachContext.new(**each_context.symbolize_keys)
      @output = Output.from_hash_array(task_outputs)
      @job_status = JobStatus.from_hash_array(task_job_statuses)
    end
    
    # 現在のJobインスタンス
    def _current_job=(job)
      @current_job = job
    end
    
    def current_job_id
      current_job.job_id
    end
    
    # EachContext関連（変更なし）
    def each_task_concurrency_key
      each_context.concurrency_key
    end
    
    def _with_each_value(task)
      raise "Nested _with_each_value calls are not allowed" if each_context.enabled?
      Enumerator.new { |y| iterate_each_value(task, y) }
    end
    
    def each_value
      raise "each_value can be called only within each_values block" unless each_context.enabled?
      each_context.value
    end
    
    def each_task_output
      raise "each_task_output can be called only within each_values block" unless each_context.enabled?
      
      task_name = each_context.task_name
      each_index = each_context.index
      output.fetch(task_name:, each_index:)
    end
    
    def _each_context
      each_context
    end
    
    # TaskOutputの追加
    def _add_task_output(task_output)
      output.add_task_output(task_output)
    end
    
    # Task管理
    def _current_task=(task)
      @current_task = task
    end
    
    def _clear_current_task
      @current_task = nil
    end
    
    private
    
    attr_reader :current_job    # DSL
    attr_reader :each_context   # EachContext
    attr_reader :current_task   # Task?
    
    # EachValueのイテレーション
    def iterate_each_value(task, yielder)
      each_name = task.each
      raise "Task #{task.name} has no each option" if each_name.nil?
      
      values = arguments.public_send(each_name)  # 引数から取得
      raise "#{each_name} is not an Array" unless values.is_a?(Array)
      
      values.each.with_index do |value, index|
        ctx = dup
        ctx.each_context.enable!(
          parent_job_id: current_job_id,
          task_name: task.name,
          index:,
          value:
        )
        yielder << ctx
      end
    end
    
    # Contextの複製（EachContext用）
    def dup
      self.class.new(
        arguments: arguments,  # イミュータブルなのでそのまま
        each_context: each_context.to_h,
        task_outputs: output.flat_task_outputs.map(&:to_h),
        task_job_statuses: job_status.flat_task_job_statuses.map(&:to_h)
      )
    end
  end
end
```

**主な変更点**:
- ✅ `raw_data`を`arguments`に置き換え（内部的には`data`）
- ✅ `reader_names`/`writer_names`を削除（Argumentsが管理）
- ✅ `method_missing`を削除（`ctx.arguments.xxx`でアクセス）
- ✅ `merge!`を削除（Argumentsがイミュータブル）
- ✅ シンプルで責務が明確

---

### 2. DSL の変更

#### 2.1 argument メソッド（context のリネーム）

```ruby
# lib/shuttle_job/dsl.rb
module DSL
  module ClassMethods
    # 旧: context メソッド
    # def context(context_name, type, default: nil)
    #   _workflow.add_context(ContextDef.new(name: context_name, type:, default:))
    # end
    
    # 新: argument メソッド
    def argument(argument_name, type, default: nil)
      _workflow.add_argument(ArgumentDef.new(name: argument_name, type:, default:))
    end
    
    # 後方互換性のため context も残す（Deprecated）
    def context(context_name, type, default: nil)
      warn "[ShuttleJob] DEPRECATED: `context` is deprecated, use `argument` instead"
      argument(context_name, type, default:)
    end
  end
end
```

**後方互換性**:
- ✅ `context`メソッドも残す（Deprecatedマーク）
- ✅ 既存コードが動作し続ける
- ✅ 警告メッセージで移行を促す

---

#### 2.2 perform_later の変更

```ruby
# lib/shuttle_job/dsl.rb
module DSL
  module ClassMethods
    def perform_later(initial_arguments = {})
      # argumentはActiveJobのargumentsとして渡す
      # Contextは内部で生成
      super(initial_arguments)
    end
  end
  
  # performメソッド
  def perform(arguments)
    # argumentsからContextを構築
    @_runner ||= _build_runner(arguments)
    @_runner.run
  end
  
  private
  
  def _build_runner(initial_arguments)
    context = self.class._workflow.build_context(initial_arguments)
    ShuttleJob::Runner.new(job: self, context:)
  end
end
```

---

### 3. Workflow の変更

```ruby
# lib/shuttle_job/workflow.rb
module ShuttleJob
  class Workflow
    def initialize
      @task_graph = TaskGraph.new
      @argument_defs = {}  # 旧: @context_defs
    end
    
    def add_argument(argument_def)
      @argument_defs[argument_def.name] = argument_def
    end
    
    def arguments
      @argument_defs.values
    end
    
    # 後方互換性
    def add_context(context_def)
      warn "[ShuttleJob] DEPRECATED: add_context is deprecated"
      add_argument(context_def)
    end
    
    def contexts
      arguments
    end
    
    def build_context(initial_arguments)
      # Hashの場合はArgumentsを構築
      if initial_arguments.is_a?(Hash)
        arguments = Arguments.from_workflow(self)
        arguments = arguments.merge!(initial_arguments)
        Context.new(arguments:)
      # 既にContextの場合はそのまま
      elsif initial_arguments.is_a?(Context)
        initial_arguments
      else
        raise ArgumentError, "Invalid argument type: #{initial_arguments.class}"
      end
    end
  end
end
```

---

### 4. ContextSerializer の削除

**ContextSerializer は不要**になります。理由：

1. **Argumentは削除**:
   - ActiveJobのargumentsとして自動永続化される
   - 独自のシリアライゼーション不要

2. **Context内部状態のみシリアライズ**:
   - Output（task_outputs）
   - JobStatus（task_job_statuses）
   - EachContext（each_context）

**新しいシリアライゼーション**:

```ruby
# lib/shuttle_job/dsl.rb
module DSL
  def serialize
    runner = _runner
    if runner.nil?
      super
    else
      # Contextの内部状態のみシリアライズ
      super.merge(
        "shuttle_job_output" => runner.context.output.flat_task_outputs.map(&:to_h),
        "shuttle_job_job_status" => runner.context.job_status.flat_task_job_statuses.map(&:to_h),
        "shuttle_job_each_context" => runner.context._each_context.to_h
      )
    end
  end
  
  def deserialize(job_data)
    super
    
    # Argumentsはすでにjob_dataに含まれている
    # Context内部状態を復元
    if job_data["shuttle_job_output"]
      @_runner = _build_runner(
        arguments,  # ActiveJobから取得
        task_outputs: job_data["shuttle_job_output"],
        task_job_statuses: job_data["shuttle_job_job_status"],
        each_context: job_data["shuttle_job_each_context"] || {}
      )
    end
  end
  
  private
  
  def _build_runner(initial_arguments, task_outputs: [], task_job_statuses: [], each_context: {})
    context = self.class._workflow.build_context(initial_arguments)
    # 内部状態を復元
    context = Context.new(
      arguments: context.arguments,
      task_outputs:,
      task_job_statuses:,
      each_context:
    )
    ShuttleJob::Runner.new(job: self, context:)
  end
end
```

---

## 影響範囲の分析

### 変更が必要なファイル

#### 1. コアファイル（7ファイル）

| ファイル | 変更内容 | 複雑度 |
|---------|---------|-------|
| `lib/shuttle_job/context_def.rb` | → `argument_def.rb` にリネーム | 低 |
| `lib/shuttle_job/arguments.rb` | 新規作成 | 中 |
| `lib/shuttle_job/context.rb` | 大幅な簡素化 | 高 |
| `lib/shuttle_job/dsl.rb` | argument メソッド追加、serialize変更 | 高 |
| `lib/shuttle_job/workflow.rb` | add_argument メソッド追加 | 中 |
| `lib/shuttle_job/context_serializer.rb` | 削除 | 低 |
| `lib/shuttle_job.rb` | ContextSerializer削除 | 低 |

#### 2. RBSファイル（7ファイル）

| ファイル | 変更内容 |
|---------|---------|
| `sig/generated/shuttle_job/context_def.rbs` | → `argument_def.rbs` |
| `sig/generated/shuttle_job/arguments.rbs` | 新規作成 |
| `sig/generated/shuttle_job/context.rbs` | 型定義変更 |
| `sig/generated/shuttle_job/dsl.rbs` | 型定義変更 |
| `sig/generated/shuttle_job/workflow.rbs` | 型定義変更 |
| `sig/generated/shuttle_job/context_serializer.rbs` | 削除 |

#### 3. テストファイル（8ファイル以上）

| ファイル | 変更内容 |
|---------|---------|
| `spec/shuttle_job/context_def_spec.rb` | → `argument_def_spec.rb` |
| `spec/shuttle_job/arguments_spec.rb` | 新規作成 |
| `spec/shuttle_job/context_spec.rb` | 大幅な書き換え |
| `spec/shuttle_job/dsl_spec.rb` | テスト追加・修正 |
| `spec/shuttle_job/workflow_spec.rb` | テスト修正 |
| `spec/shuttle_job/context_serializer_spec.rb` | 削除 |
| `spec/shuttle_job/runner_spec.rb` | `ctx.xxx` → `ctx.argument.xxx` |
| その他すべてのspec | アクセス方法の変更 |

---

## 実装計画

### Phase 1: 新クラスの作成（1-2日）

**Goal**: 新しいクラスを実装し、単体テスト作成

1. ✅ `ArgumentDef` クラス作成（ContextDef からコピー）
2. ✅ `Arguments` クラス作成（新規）
3. ✅ 単体テスト作成
   - `spec/shuttle_job/argument_def_spec.rb`
   - `spec/shuttle_job/arguments_spec.rb`

**検証**: 新クラスが期待通り動作することを確認

---

### Phase 2: Context の簡素化（2-3日）

**Goal**: Context クラスをリファクタリング

1. ✅ `Context` クラスの書き換え
   - `raw_data` → `arguments`（内部的には`data`）
   - `method_missing` 削除
   - `merge!` 削除
2. ✅ テスト修正
   - `spec/shuttle_job/context_spec.rb`
3. ✅ 動作確認

**検証**: Context が Arguments を保持し、正しく動作することを確認

---

### Phase 3: DSL と Workflow の変更（2-3日）

**Goal**: DSL と Workflow を新設計に対応

1. ✅ `Workflow` クラス変更
   - `add_argument` メソッド追加
   - `build_context` メソッド変更
2. ✅ `DSL` クラス変更
   - `argument` メソッド追加
   - `context` メソッドを Deprecated に
   - `serialize`/`deserialize` 変更
3. ✅ テスト修正
   - `spec/shuttle_job/dsl_spec.rb`
   - `spec/shuttle_job/workflow_spec.rb`

**検証**: DSL で `argument` が使えることを確認

---

### Phase 4: ContextSerializer の削除（1日）

**Goal**: ContextSerializer を削除し、新しいシリアライゼーションに移行

1. ✅ `ContextSerializer` クラス削除
2. ✅ `lib/shuttle_job.rb` から登録削除
3. ✅ `DSL#serialize` / `DSL#deserialize` の実装
4. ✅ テスト削除
   - `spec/shuttle_job/context_serializer_spec.rb`

**検証**: シリアライゼーションが正しく動作することを確認

---

### Phase 5: 全テストの修正（2-3日）

**Goal**: すべてのテストを新しいアクセス方法に対応

1. ✅ Runner のテスト修正
   - `ctx.xxx` → `ctx.arguments.xxx`
2. ✅ 統合テストの修正
3. ✅ すべてのテストが通ることを確認

**検証**: 全テスト（223 examples）がパス

---

### Phase 6: ドキュメント更新（1-2日）

**Goal**: ドキュメントを新設計に更新

1. ✅ GUIDE.md の更新
   - `context` → `argument`
   - アクセス方法の変更
2. ✅ README.md の更新
3. ✅ CHANGELOG.md に破壊的変更を記載

---

### Phase 7: 後方互換性の検証（1日）

**Goal**: 既存コードが動作し続けることを確認

1. ✅ Deprecated な `context` メソッドの動作確認
2. ✅ 警告メッセージの確認
3. ✅ 移行ガイドの作成

---

## 実装見積もり

### 合計工数: **10-15 日**

| Phase | 工数 | 複雑度 |
|-------|-----|-------|
| Phase 1: 新クラス作成 | 1-2日 | 低 |
| Phase 2: Context 簡素化 | 2-3日 | 高 |
| Phase 3: DSL/Workflow 変更 | 2-3日 | 高 |
| Phase 4: Serializer 削除 | 1日 | 中 |
| Phase 5: 全テスト修正 | 2-3日 | 中 |
| Phase 6: ドキュメント更新 | 1-2日 | 低 |
| Phase 7: 後方互換性検証 | 1日 | 低 |

---

## メリットとデメリット

### ✅ メリット

1. **責務の明確化**
   - Arguments: イミュータブルな初期引数
   - Output: タスク間の結果受け渡し
   - Context: 全体の統合（読み取り専用）

2. **バグの防止**
   - Argumentsの誤った書き換えを防止
   - 型安全性の向上

3. **コードの可読性向上**
   - `ctx.arguments.user_id` で引数とわかる
   - `ctx.output.task_name` で結果とわかる

4. **シリアライゼーションの簡素化**
   - ActiveJobの標準機能を活用
   - 独自実装の削減

5. **パフォーマンス向上**
   - 不要なシリアライゼーションの削減
   - メモリ使用量の削減

### ⚠️ デメリット

1. **破壊的変更**
   - 既存コードの修正が必要
   - `ctx.xxx` → `ctx.arguments.xxx`

2. **移行コスト**
   - 全テストの修正
   - ドキュメントの更新
   - ユーザーへの周知

3. **学習コスト**
   - 新しいアクセス方法の習得
   - 概念の理解

---

## 後方互換性の戦略

### 1. Deprecated警告

```ruby
# context メソッドは残す
def context(context_name, type, default: nil)
  warn "[ShuttleJob] DEPRECATED: `context` is deprecated, use `argument` instead"
  argument(context_name, type, default:)
end
```

### 2. 移行期間

- **v0.x.x**: `context` と `argument` 両方サポート
- **v1.0.0**: `context` を削除（Major Version Up）

### 3. 移行ガイド

```ruby
# Before (旧設計)
class MyJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :user_id, "Integer"
  context :items, "Array[String]"
  
  task :process do |ctx|
    user_id = ctx.user_id
    items = ctx.items
    ctx.result = process(user_id, items)
  end
end

# After (新設計)
class MyJob < ApplicationJob
  include ShuttleJob::DSL
  
  argument :user_id, "Integer"
  argument :items, "Array[String]"
  
  task :process, output: { result: "String" } do |ctx|
    user_id = ctx.arguments.user_id
    items = ctx.arguments.items
    { result: process(user_id, items) }
  end
end
```

---

## リスク分析

### 高リスク

1. **既存ユーザーへの影響**
   - **リスク**: 既存コードが動かなくなる
   - **対策**: Deprecated警告で段階的移行

2. **テストの大量修正**
   - **リスク**: テスト修正に時間がかかる
   - **対策**: 段階的な修正、自動化ツールの活用

### 中リスク

3. **シリアライゼーションのバグ**
   - **リスク**: データ損失や復元エラー
   - **対策**: 十分なテスト、段階的リリース

4. **パフォーマンス問題**
   - **リスク**: 予期しないパフォーマンス低下
   - **対策**: ベンチマークテスト

### 低リスク

5. **ドキュメントの不整合**
   - **リスク**: ユーザーの混乱
   - **対策**: 丁寧なドキュメント更新

---

## 次のステップ

### 推奨アクション

この設計見直しは**非常に理にかなっており、実装を推奨**します。

#### Option 1: 段階的実装（推奨）

**Week 1**: Phase 1-2（新クラス作成、Context簡素化）  
**Week 2**: Phase 3-4（DSL変更、Serializer削除）  
**Week 3**: Phase 5-7（テスト修正、ドキュメント更新）

#### Option 2: 一括実装

**2-3週間**: 全Phase を一気に実装（高リスク）

#### Option 3: プロトタイプ検証

**3-5日**: Phase 1-2 のみ実装し、動作確認後に判断

---

### 実装を開始する場合

1. **Feature Branch 作成**
   ```bash
   git checkout -b feature/context-to-argument-refactor
   ```

2. **Phase 1 から順次実装**
   - ArgumentDef 作成
   - Argument 作成
   - テスト作成

3. **継続的な動作確認**
   - 各Phase完了時にテスト実行
   - カバレッジ維持

---

## まとめ

この設計見直しは、Output機能の導入により明確になった責務の分離を実現するものです。

**主な変更**:
- ✅ `context` → `argument`（DSL）
- ✅ `ctx.xxx` → `ctx.arguments.xxx`（アクセス方法）
- ✅ ContextSerializer 削除
- ✅ Argumentsのイミュータブル化

**効果**:
- ✅ 責務の明確化（Arguments: 引数、Output: 結果）
- ✅ バグの防止（イミュータブル化）
- ✅ コードの可読性向上（`ctx.arguments.xxx`）
- ✅ パフォーマンス向上（シリアライゼーション削減）

**工数**: 10-15日

**リスク**: 中（後方互換性で軽減可能）

---

**推奨**: この設計見直しを実装することを強く推奨します。段階的な実装で安全に移行できます。

