# frozen_string_literal: true

require "concurrent"
require_relative "signalize/version"

module Signalize
  class Error < StandardError; end

  class << self
    def global_map_accessor(name)
      define_singleton_method "#{name}" do
        GLOBAL_MAP[name]
      end
      define_singleton_method "#{name}=" do |value|
        GLOBAL_MAP[name] = value
      end
    end
  end

  def self.cycle_detected
	  raise Signalize::Error, "Cycle detected"
  end

  def self.mutation_detected
	  raise Signalize::Error, "Computed cannot have side-effects"
  end

  RUNNING = 1 << 0
  NOTIFIED = 1 << 1
  OUTDATED = 1 << 2
  DISPOSED = 1 << 3
  HAS_ERROR = 1 << 4
  TRACKING = 1 << 5

  GLOBAL_MAP = Concurrent::Map.new

  # Computed | Effect | nil
  global_map_accessor :eval_context
  self.eval_context = nil

  # Used by `untracked` method
  global_map_accessor :untracked_depth
  self.untracked_depth = 0

  # Effects collected into a batch.
  global_map_accessor :batched_effect
  self.batched_effect = nil
  global_map_accessor :batch_depth
  self.batch_depth = 0
  global_map_accessor :batch_iteration
  self.batch_iteration = 0

  # NOTE: we have removed the global version optimization for Ruby, due to
  # the possibility of long-running server processes and the number reaching
  # a dangerously high integer value.
  #
  # global_map_accessor :global_version
  # self.global_version = 0

  Node = Struct.new(
    :_version,
    :_source,
    :_prev_source,
    :_next_source,
    :_target,
    :_prev_target,
    :_next_target,
    :_rollback_node,
    keyword_init: true
  )

  class << self
    ## Batch-related helpers ##

    def start_batch
      self.batch_depth += 1
    end
  
    def end_batch
      if batch_depth > 1
        self.batch_depth -= 1
        return
      end
      error = nil
      hasError = false
    
      while batched_effect.nil?.!
        effect = batched_effect
        self.batched_effect = nil
    
        self.batch_iteration += 1
        while effect.nil?.!
          nxt = effect._next_batched_effect
          effect._next_batched_effect = nil
          effect._flags &= ~NOTIFIED
          unless (effect._flags & DISPOSED).nonzero? && needs_to_recompute(effect)
            begin
              effect._callback
            rescue StandardError => err
              unless hasError
                error = err
                hasError = true
              end
            end
          end

          effect = nxt
        end
      end

      self.batch_iteration = 0
      self.batch_depth -= 1
    
      raise error if hasError
    end

    def batch
      return yield unless batch_depth.zero?

      start_batch

      begin
        return yield
      ensure
        end_batch
      end
    end

    ## Signal-related helpers ##

    def add_dependency(signal)
      return nil if eval_context.nil?

      node = signal._node
      if node.nil? || node._target != eval_context
        # /**
        # * `signal` is a new dependency. Create a new dependency node, and set it
        # * as the tail of the current context's dependency list. e.g:
        # *
        # * { A <-> B       }
        # *         ↑     ↑
        # *        tail  node (new)
        # *               ↓
        # * { A <-> B <-> C }
        # *               ↑
        # *              tail (evalContext._sources)
        # */
        node = Node.new(
          _version: 0,
          _source: signal,
          _prev_source: eval_context._sources,
          _next_source: nil,
          _target: eval_context,
          _prev_target: nil,
          _next_target: nil,
          _rollback_node: node,
        )

        unless eval_context._sources.nil?
          eval_context._sources._next_source = node
        end
        eval_context._sources = node
        signal._node = node

        # Subscribe to change notifications from this dependency if we're in an effect
        # OR evaluating a computed signal that in turn has subscribers.
        if (eval_context._flags & TRACKING).nonzero?
          signal._subscribe(node)
        end
        return node
      elsif node._version == -1
        # `signal` is an existing dependency from a previous evaluation. Reuse it.
        node._version = 0

        # /**
        # * If `node` is not already the current tail of the dependency list (i.e.
        # * there is a next node in the list), then make the `node` the new tail. e.g:
        # *
        # * { A <-> B <-> C <-> D }
        # *         ↑           ↑
        # *        node   ┌─── tail (evalContext._sources)
        # *         └─────│─────┐
        # *               ↓     ↓
        # * { A <-> C <-> D <-> B }
        # *                     ↑
        # *                    tail (evalContext._sources)
        # */
        unless node._next_source.nil?
          node._next_source._prev_source = node._prev_source

          unless node._prev_source.nil?
            node._prev_source._next_source = node._next_source
          end

          node._prev_source = eval_context._sources
          node._next_source = nil

          eval_context._sources._next_source = node
          eval_context._sources = node
        end

        # We can assume that the currently evaluated effect / computed signal is already
        # subscribed to change notifications from `signal` if needed.
        return node
      end

      nil
    end

    ## Computed/Effect-related helpers ##

    def needs_to_recompute(target)
      # Check the dependencies for changed values. The dependency list is already
      # in order of use. Therefore if multiple dependencies have changed values, only
      # the first used dependency is re-evaluated at this point.
      node = target._sources
      while node.nil?.!
        # If there's a new version of the dependency before or after refreshing,
        # or the dependency has something blocking it from refreshing at all (e.g. a
        # dependency cycle), then we need to recompute.
        if node._source._version != node._version || !node._source._refresh || node._source._version != node._version
          return true
        end
        node = node._next_source
      end
      # If none of the dependencies have changed values since last recompute then
      # there's no need to recompute.
      false
    end

    def prepare_sources(target)
      # /**
      # * 1. Mark all current sources as re-usable nodes (version: -1)
      # * 2. Set a rollback node if the current node is being used in a different context
      # * 3. Point 'target._sources' to the tail of the doubly-linked list, e.g:
      # *
      # *    { undefined <- A <-> B <-> C -> undefined }
      # *                   ↑           ↑
      # *                   │           └──────┐
      # * target._sources = A; (node is head)  │
      # *                   ↓                  │
      # * target._sources = C; (node is tail) ─┘
      # */
      node = target._sources
      while node.nil?.!
        rollbackNode = node._source._node
        node._rollback_node = rollbackNode unless rollbackNode.nil?
        node._source._node = node
        node._version = -1

        if node._next_source.nil?
          target._sources = node
          break
        end

        node = node._next_source
      end
    end

    def cleanup_sources(target)
      node = target._sources
      head = nil

      # /**
      # * At this point 'target._sources' points to the tail of the doubly-linked list.
      # * It contains all existing sources + new sources in order of use.
      # * Iterate backwards until we find the head node while dropping old dependencies.
      # */
      while node.nil?.!
        prev = node._prev_source

        # /**
        # * The node was not re-used, unsubscribe from its change notifications and remove itself
        # * from the doubly-linked list. e.g:
        # *
        # * { A <-> B <-> C }
        # *         ↓
        # *    { A <-> C }
        # */
        if node._version == -1
          node._source._unsubscribe(node)

          unless prev.nil?
            prev._next_source = node._next_source
          end
          unless node._next_source.nil?
            node._next_source._prev_source = prev
          end
        else
          # /**
          # * The new head is the last node seen which wasn't removed/unsubscribed
          # * from the doubly-linked list. e.g:
          # *
          # * { A <-> B <-> C }
          # *   ↑     ↑     ↑
          # *   │     │     └ head = node
          # *   │     └ head = node
          # *   └ head = node
          # */
          head = node
        end

        node._source._node = node._rollback_node
        unless node._rollback_node.nil?
          node._rollback_node = nil
        end

        node = prev
      end

      target._sources = head
    end

    ## Effect-related helpers ##

    def cleanup_effect(effect)
      cleanup = effect._cleanup
      effect._cleanup = nil

      if cleanup.is_a?(Proc)
        start_batch

        # Run cleanup functions always outside of any context.
        prev_context = eval_context
        self.eval_context = nil
        begin
          cleanup.()
        rescue StandardError => err
          effect._flags &= ~RUNNING
          effect._flags |= DISPOSED
          dispose_effect(effect)
          raise err
        ensure
          self.eval_context = prev_context
          end_batch
        end
      end
    end

    def dispose_effect(effect)
      node = effect._sources
      while node.nil?.!
        node._source._unsubscribe(node)
        node = node._next_source
      end
      effect._compute = nil
      effect._sources = nil

      cleanup_effect(effect)
    end

    def end_effect(effect, prev_context, *_) # allow additional args for currying
      raise Signalize::Error, "Out-of-order effect" if eval_context != effect

      cleanup_sources(effect)
      self.eval_context = prev_context

      effect._flags &= ~RUNNING
      dispose_effect(effect) if (effect._flags & DISPOSED).nonzero?
      end_batch
    end
  end

  class Signal
    attr_accessor :_version, :_node, :_targets

    def initialize(value)
      @value = value
      @_version = 0;
      @_node = nil
      @_targets = nil
    end

    def _refresh = true

    def _subscribe(node)
      if _targets != node && node._prev_target.nil?
        node._next_target = _targets
        _targets._prev_target = node if !_targets.nil?
        self._targets = node
      end
    end

    def _unsubscribe(node)
      # Only run the unsubscribe step if the signal has any subscribers to begin with.
      if !_targets.nil?
        prev = node._prev_target
        nxt = node._next_target
        if !prev.nil?
          prev._next_target = nxt
          node._prev_target = nil
        end
        if !nxt.nil?
          nxt._prev_target = prev
          node._next_target = nil
        end
        self._targets = nxt if node == _targets
      end
    end

    def subscribe(&fn)
      signal = self
      this = Effect.allocate
      this.send(:initialize, -> {
        value = signal.value
        flag = this._flags & TRACKING
        this._flags &= ~TRACKING;
        begin
          fn.(value)
        ensure
          this._flags |= flag
        end
      })

      Signalize.effect(this)
    end

    def value
      node = Signalize.add_dependency(self)
      node._version = _version unless node.nil?
      @value
    end

    def value=(value)
      Signalize.mutation_detected if Signalize.eval_context.is_a?(Signalize::Computed)

      if value != @value
        Signalize.cycle_detected if Signalize.batch_iteration > 100

        @value = value;
        @_version += 1
        # Signalize.global_version += 1

        Signalize.start_batch
        begin
          node = _targets
          while node.nil?.!
            node._target._notify
            node = node._next_target
          end
        ensure
          Signalize.end_batch
        end
      end
    end

    def to_s
      @value.to_s
    end

    def peek = @value

    def inspect
      "#<#{self.class} value: #{peek.inspect}>"
    end
  end

  class Computed < Signal
    attr_accessor :_compute, :_sources, :_flags

    def initialize(compute)
      super(nil)

      @_compute = compute
      @_sources = nil
      # @_global_version = Signalize.global_version - 1
      @_flags = OUTDATED
    end

    def _refresh
      @_flags &= ~NOTIFIED

      return false if (@_flags & RUNNING).nonzero?

      # If this computed signal has subscribed to updates from its dependencies
      # (TRACKING flag set) and none of them have notified about changes (OUTDATED
      # flag not set), then the computed value can't have changed.
      return true if (@_flags & (OUTDATED | TRACKING)) == TRACKING

      @_flags &= ~OUTDATED
    
      # NOTE: performance optimization removed.
      #
      # if @_global_version == Signalize.global_version
      #   return true
      # end
      # @_global_version = Signalize.global_version

      # Mark this computed signal running before checking the dependencies for value
      # changes, so that the RUNNING flag can be used to notice cyclical dependencies.
      @_flags |= RUNNING
      if @_version > 0 && !Signalize.needs_to_recompute(self)
        @_flags &= ~RUNNING
        return true
      end
    
      prev_context = Signalize.eval_context
      begin
        Signalize.prepare_sources(self)
        Signalize.eval_context = self
        value = @_compute.()
        if (@_flags & HAS_ERROR).nonzero? || @value != value || @_version == 0
          @value = value
          @_flags &= ~HAS_ERROR
          @_version += 1
        end
      rescue StandardError => err
        @value = err;
        @_flags |= HAS_ERROR
        @_version += 1
      end
      Signalize.eval_context = prev_context
      Signalize.cleanup_sources(self)
      @_flags &= ~RUNNING

      true
    end

    def _subscribe(node)
      if @_targets.nil?
        @_flags |= OUTDATED | TRACKING

        # A computed signal subscribes lazily to its dependencies when the it
        # gets its first subscriber.

        # RUBY NOTE: if we redefine `node`` here, it messes with `node` top method scope!
        # So we'll use a new variable name `snode`
        snode = @_sources
        while snode.nil?.!
          snode._source._subscribe(snode)
          snode = snode._next_source
        end
      end
      super(node)
    end

    def _unsubscribe(node)
      # Only run the unsubscribe step if the computed signal has any subscribers.
      unless @_target.nil?
        super(node)

        # Computed signal unsubscribes from its dependencies when it loses its last subscriber.
        # This makes it possible for unreferences subgraphs of computed signals to get garbage collected.
        if @_targets.nil?
          @_flags &= ~TRACKING

          node = @_sources

          while node.nil?.!
            node._source._unsubscribe(node)
            node = node._next_source
          end
        end
      end
    end

    def _notify
      unless (@_flags & NOTIFIED).nonzero?
        @_flags |= OUTDATED | NOTIFIED

        node = @_targets
        while node.nil?.!
          node._target._notify
          node = node._next_target
        end
      end
    end

    def peek
      Signalize.cycle_detected unless _refresh

      raise @value if (@_flags & HAS_ERROR).nonzero?

      @value
    end

    def value
      Signalize.cycle_detected if (@_flags & RUNNING).nonzero?

      node = Signalize.add_dependency(self)
      _refresh

      node._version = @_version unless node.nil?

      raise @value if (@_flags & HAS_ERROR).nonzero?

      @value
    end
  end

  class Effect
    attr_accessor :_compute, :_cleanup, :_sources, :_next_batched_effect, :_flags

    def initialize(compute)
      @_compute = compute
	    @_cleanup = nil
      @_sources = nil
      @_next_batched_effect = nil
      @_flags = TRACKING
    end

    def _callback
      finis = _start

      begin
        compute_executed = false
        @_cleanup = _compute.() if (@_flags & DISPOSED).zero? && @_compute.nil?.!
        compute_executed = true
      ensure
        unless compute_executed
          raise Signalize::Error, "Early return or break detected in effect block"
        end
        finis.(nil) # TODO: figure out this weird shit
      end
    end

    def _start
      Signalize.cycle_detected if (@_flags & RUNNING).nonzero?

      @_flags |= RUNNING
      @_flags &= ~DISPOSED
      Signalize.cleanup_effect(self)
      Signalize.prepare_sources(self)

      Signalize.start_batch
      prev_context = Signalize.eval_context
      Signalize.eval_context = self

      Signalize.method(:end_effect).curry(3).call(self, prev_context) # HUH
    end

    def _notify
      unless (@_flags & NOTIFIED).nonzero?
        @_flags |= NOTIFIED
        @_next_batched_effect = Signalize.batched_effect
        Signalize.batched_effect = self
      end
    end

    def _dispose
	    @_flags |= DISPOSED

      Signalize.dispose_effect(self) unless (@_flags & RUNNING).nonzero?
    end
  end

  module API  
    def signal(value)
      Signal.new(value)
    end

    def computed(&block)
      Computed.new(block)
    end

    def effect(effect_instance = nil, &block)
      effect = effect_instance || Effect.new(block)

      begin
        effect._callback
      rescue StandardError => err
        effect._dispose
        raise err
      end

      effect.method(:_dispose)
    end

    def batch
      return yield unless Signalize.batch_depth.zero?

      Signalize.start_batch

      begin
        return yield
      ensure
        Signalize.end_batch
      end
    end

    def untracked
      return yield unless Signalize.untracked_depth.zero?

      prev_context = Signalize.eval_context
      Signalize.eval_context = nil
      Signalize.untracked_depth += 1

      begin
        return yield
      ensure
        Signalize.untracked_depth -= 1
        Signalize.eval_context = prev_context
      end
    end
  end

  extend API
end
