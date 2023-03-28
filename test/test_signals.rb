# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require_relative "test_helper"

class Spy
  def initialize(&block)
    @block = block
    @called_times = 0
    @called_with = nil
    @return_value = nil
  end

  def to_proc = method(:call).to_proc

  attr :called_times
  attr :called_with
  attr :return_value
  def reset_history! = @called_times = 0

  def call(*args, &)
    @called_times += 1
    @called_with = args
    @return_value = @block.call(*args, &)
  end
end

describe "Signals" do
  include Signalize::API

  describe "Signal" do
    it "should return a value" do
      v = [1, 2]
      s = signal(v)
      _(s.value).must_equal(v)
    end

    it "should be an instance of Signalize::Signal" do
      _(signal(0)).must_be_instance_of(Signalize::Signal)
    end

    it "should support .to_s" do
      s = signal(123)
      assert_equal("123", s.to_s)
    end

    it "should notify other listeners of changes after one listener is disposed" do
      s = signal(0)
      spy1 = Spy.new { s.value }
      spy2 = Spy.new { s.value }
      spy3 = Spy.new { s.value }

      effect(&spy1)

      dispose = effect(&spy2)
      effect(&spy3)

      assert_equal(1, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(1, spy3.called_times)

      dispose.call

      s.value = 1

      assert_equal(2, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(2, spy3.called_times)
    end

    describe "peek()" do
      it "should get a value" do
        s = signal(1)
        _(s.peek).must_equal(1)
      end

      it "should get the updated value after a value change" do
        s = signal(1)
        s.value = 2
        _(s.peek).must_equal(2)
      end

      it "should not make the surrounding effect depend on the signal" do
        s = signal(1)
        spy = Spy.new { s.peek }

        effect(&spy)
        assert_equal(1, spy.called_times)

        s.value = 2
        assert_equal(1, spy.called_times)
      end

      it "should not make the surrounding computed signal depend on the signal" do
        s = signal(1)
        spy = Spy.new { s.peek }

        d = computed(&spy)

        d.value
        assert_equal(1, spy.called_times)

        s.value = 2
        d.value
        assert_equal(1, spy.called_times)
      end
    end

    describe "subscribe()" do
      it "should subscribe to a signal" do
        spy = Spy.new {}
        a = signal(1)
        a.subscribe(&spy)
        assert(1, spy.called_times)
      end

      it "should unsubscribe from a signal" do
        spy = Spy.new {}
        a = signal(1)

        dispose = a.subscribe(&spy)
        dispose.call

        spy.reset_history!

        a.value = 2
        assert(0, spy.called_times)
      end

      it "should not start triggering on when a signal accessed in the callback changes" do
        spy = Spy.new {}
        a = signal(0)
        b = signal(0)

        a.subscribe do
          b.value
          spy.call
        end

        assert_equal(1, spy.called_times)
        spy.reset_history!

        b.value += 1

        assert_equal(0, spy.called_times)
      end

      it "should not cause surrounding effect to subscribe to changes to a signal accessed in the callback" do
        spy = Spy.new {}
        a = signal(0)
        b = signal(0)

        effect do
          a.subscribe { b.value }
          spy.call
        end

        assert_equal(1, spy.called_times)
        spy.reset_history!

        b.value += 1

        assert_equal(0, spy.called_times)
      end
    end
  end

  describe "effect()" do
    it "should init with value" do
      s = signal(123)
      spy = Spy.new {}
      a = signal(0)
      b = signal(0)

      effect do
        a.subscribe { b.value }
        spy.call
      end

      assert_equal(1, spy.called_times)
      spy.reset_history!

      b.value += 1

      assert_equal(0, spy.called_times)
    end

    it "should subscribe to signals" do
      s = signal(123)
      spy = Spy.new { s.value }
      effect(&spy)
      spy.reset_history!

      s.value = 42
      assert_equal(1, spy.called_times)
      assert_equal(42, spy.return_value)
    end

    it "should subscribe to multiple signals" do
      a = signal("a")
      b = signal("b")
      spy = Spy.new { a.value + " " + b.value }
      effect(&spy)
      spy.reset_history!

      a.value = "aa"
      b.value = "bb"
      assert_equal("aa bb", spy.return_value)
    end

    it "should dispose of subscriptions" do
      a = signal("a")
      b = signal("b")
      spy = Spy.new { a.value + " " + b.value }
      dispose = effect(&spy)
      spy.reset_history!

      dispose.call
      assert_equal(0, spy.called_times)

      a.value = "aa"
      b.value = "bb"

      assert_equal(0, spy.called_times)
    end

    it "should unsubscribe from signal" do
      s = signal(123)
      spy = Spy.new { s.value }
      unsub = effect(&spy)
      spy.reset_history!

      unsub.call
      s.value = 42

      assert_equal(0, spy.called_times)
    end

    it "should conditionally unsubscribe from signals" do
      a = signal("a")
      b = signal("b")
      cond = signal(true)

      spy = Spy.new { cond.value ? a.value : b.value }

      effect(&spy)
      assert_equal(1, spy.called_times)

      b.value = "bb"
      assert_equal(1, spy.called_times)

      cond.value = false
      assert_equal(2, spy.called_times)

      spy.reset_history!

      a.value = "aaa"
      assert_equal(0, spy.called_times)
    end

    it "should batch writes" do
      a = signal("a")
      spy = Spy.new { a.value }
      effect(&spy)
      spy.reset_history!

      effect do
        a.value = "aa"
        a.value = "aaa"
      end

      assert_equal(1, spy.called_times)
    end

    it "should call the cleanup callback before the next run" do
      a = signal(0)
      spy = Spy.new {}

      effect do
        a.value
        spy.to_proc
      end

      assert_equal(0, spy.called_times)
      a.value = 1
      assert_equal(1, spy.called_times)
      a.value = 2
      assert_equal(2, spy.called_times)
    end

    it "should call only the callback from the previous run" do
      spy1 = Spy.new {}
      spy2 = Spy.new {}
      spy3 = Spy.new {}
      a = signal(spy1)

      effect { a.value.to_proc }

      assert_equal(0, spy1.called_times)
      assert_equal(0, spy2.called_times)
      assert_equal(0, spy3.called_times)

      a.value = spy2
      assert_equal(1, spy1.called_times)
      assert_equal(0, spy2.called_times)
      assert_equal(0, spy3.called_times)

      a.value = spy3
      assert_equal(1, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(0, spy3.called_times)
    end

    it "should call the cleanup callback function when disposed" do
      spy = Spy.new {}

      dispose = effect { spy.to_proc }

      assert_equal(0, spy.called_times)
      dispose.call
      assert_equal(1, spy.called_times)
    end

    it "should not recompute if the effect has been notified about changes, but no direct dependency has actually changed" do
      s = signal(0)
      c =
        computed do
          s.value
          0
        end
      spy = Spy.new { c.value }
      effect(&spy)
      assert_equal(1, spy.called_times)
      spy.reset_history!

      s.value = 1
      assert_equal(0, spy.called_times)
    end

    it "should not recompute dependencies unnecessarily" do
      spy = Spy.new {}
      a = signal(0)
      b = signal(0)
      c =
        computed do
          b.value
          spy.call
        end
      effect { c.value if a.value == 0 }
      assert_equal(1, spy.called_times)

      batch do
        b.value = 1
        a.value = 1
      end
      assert_equal(1, spy.called_times)
    end

    it "should not recompute dependencies out of order" do
      a = signal(1)
      b = signal(1)
      c = signal(1)

      spy = Spy.new { c.value }
      d = computed(&spy)

      effect do
        if a.value > 0
          b.value
          d.value
        else
          b.value
        end
      end
      spy.reset_history!

      batch do
        a.value = 2
        b.value = 2
        c.value = 2
      end
      assert_equal(1, spy.called_times)
      spy.reset_history!

      batch do
        a.value = -1
        b.value = -1
        c.value = -1
      end
      assert_equal(0, spy.called_times)
      spy.reset_history!
    end

    it "should recompute if a dependency changes during computation after becoming a dependency" do
      a = signal(0)
      spy = Spy.new { a.value += 1 if a.value == 0 }
      effect(&spy)
      assert_equal(2, spy.called_times)
    end

    it "should run the cleanup in an implicit batch" do
      a = signal(0)
      b = signal("a")
      c = signal("b")
      spy = Spy.new {}

      effect do
        b.value
        c.value
        spy.call(b.value + c.value)
      end

      effect do
        a.value
        -> {
          b.value = "x"
          c.value = "y"
        }
      end

      assert_equal(1, spy.called_times)
      spy.reset_history!

      a.value = 1
      assert_equal(1, spy.called_times)
      assert_equal(["xy"], spy.called_with)
    end

    it "should not retrigger the effect if the cleanup modifies one of the dependencies" do
      a = signal(0)
      spy = Spy.new {}

      effect do
        spy.call(a.value)
        -> { a.value = 2 }
      end
      assert_equal(1, spy.called_times)
      spy.reset_history!

      a.value = 1
      assert_equal(1, spy.called_times)
      assert_equal([2], spy.called_with)
    end

    it "should run the cleanup if the effect disposes itself" do
      a = signal(0)
      spy = Spy.new {}

      dispose =
        effect do
          if a.value > 0
            dispose.call
            spy.to_proc
          else
            nil
          end
        end
      assert_equal(0, spy.called_times)
      a.value = 1
      assert_equal(1, spy.called_times)
      a.value = 2
      assert_equal(1, spy.called_times)
    end

    it "should not run the effect if the cleanup function disposes it" do
      a = signal(0)
      spy = Spy.new {}

      dispose =
        effect do
          a.value
          spy.call
          -> { dispose.call }
        end
      assert_equal(1, spy.called_times)
      a.value = 1
      assert_equal(1, spy.called_times)
    end

    it "should not subscribe to anything if first run raises" do
      s = signal(0)
      spy =
        Spy.new do
          s.value
          raise "test"
        end
      e = assert_raises(RuntimeError) { effect(&spy) }
      assert_equal("test", e.message)
      assert_equal(1, spy.called_times)

      s.value += 1
      assert_equal(1, spy.called_times)
    end

    it "should reset the cleanup if the effect raises" do
      a = signal(0)
      spy = Spy.new {}

      effect do
        if a.value == 0
          spy.to_proc
        else
          raise "hello"
        end
      end
      assert_equal(0, spy.called_times)
      e = assert_raises(RuntimeError) { a.value = 1 }
      assert_equal("hello", e.message)
      assert_equal(1, spy.called_times)
      a.value = 0
      assert_equal(1, spy.called_times)
    end

    it "should dispose the effect if the cleanup callback raises" do
      a = signal(0)
      spy = Spy.new {}

      effect do
        if a.value == 0
          -> { raise "hello" }
        else
          spy.call
        end
      end
      assert_equal(0, spy.called_times)
      e = assert_raises(RuntimeError) { a.value += 1 }
      assert_equal("hello", e.message)
      assert_equal(0, spy.called_times)
      a.value += 1
      assert_equal(0, spy.called_times)
    end

    it "should run cleanups outside any evaluation context" do
      spy = Spy.new {}
      a = signal(0)
      b = signal(0)
      c =
        computed do
          effect { -> { b.value } } if a.value == 0
          a.value
        end

      effect do
        spy.call
        c.value
      end
      assert_equal(1, spy.called_times)
      spy.reset_history!

      a.value = 1
      assert_equal(1, spy.called_times)
      spy.reset_history!

      b.value = 1
      assert_equal(0, spy.called_times)
    end

    it "should raise on cycles" do
      a = signal(0)
      i = 0

      fn = -> {
        effect do
          # Prevent test suite from spinning if limit is not hit
          if (i += 1) > 200
            raise "test failed"
          end
          a.value
          a.value = Float::NAN
        end
      }

      assert_raises(Signalize::Error, &fn)
    end

    it "should raise on indirect cycles" do
      a = signal(0)
      i = 0

      c =
        computed do
          a.value
          a.value = Float::NAN
          Float::NAN
        end

      fn = -> {
        effect do
          # Prevent test suite from spinning if limit is not hit
          if (i += 1) > 200
            raise "test failed"
          end
          c.value
        end
      }

      assert_raises(Signalize::Error, &fn)
    end

    it "should allow disposing the effect multiple times" do
      dispose = effect { nil }
      dispose.call
      begin
        dispose.call
      rescue => e
        assert(true, "the previous line should not raise")
      end
    end

    it "should allow disposing a running effect" do
      a = signal(0)
      spy = Spy.new {}
      dispose =
        effect do
          if a.value == 1
            dispose.call
            spy.call
          end
        end
      assert_equal(0, spy.called_times)
      a.value = 1
      assert_equal(1, spy.called_times)
      a.value = 2
      assert_equal(1, spy.called_times)
    end

    it "should not run if it's first been triggered and then disposed in a batch" do
      a = signal(0)
      spy = Spy.new { a.value }
      dispose = effect(&spy)
      spy.reset_history!

      batch do
        a.value = 1
        dispose.call
      end

      assert_equal(0, spy.called_times)
    end

    it "should not run if it's been triggered, disposed and then triggered again in a batch" do
      a = signal(0)
      spy = Spy.new { a.value }
      dispose = effect(&spy)
      spy.reset_history!

      batch do
        a.value = 1
        dispose.call
        a.value = 2
      end

      assert_equal(0, spy.called_times)
    end
  end

  describe "internals" do
    # Test internal behavior depended on by Preact & React integrations
    # it "should pass in the effect instance in callback's `this`" do
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #   expect(typeof e._start).to.equal("function")
    #   expect(typeof e._dispose).to.equal("function")
    # end
    #
    # it "should allow setting _callback that replaces the default functionality" do
    #   a = signal(0)
    #   oldSpy = Spy.new {}
    #   newSpy = Spy.new {}
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #     a.value
    #     oldspy.call
    #   end
    #   oldSpy.reset_history!
    #
    #   e._callback = newSpy
    #   a.value = 1
    #
    #   assert_equal(0, oldSpy.called_times)
    #   expect(newSpy).to.be.called
    # end
    #
    # it "should return a function for closing the effect scope from _start" do
    #   s = signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   spy = Spy.new {}
    #   e._callback = spy
    #
    #   done1 = e._start()
    #   s.value
    #   done1()
    #   assert_equal(0, spy.called_times)
    #
    #   s.value = 2
    #   expect(spy).to.be.called
    #   spy.reset_history!
    #
    #   done2 = e._start()
    #   done2()
    #
    #   s.value = 3
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should raise on out-of-order start1-start2-end1 sequences" do
    #   e1: any
    #   effect(function (this: any) {
    #     e1 = this
    #   end
    #
    #   e2: any
    #   effect(function (this: any) {
    #     e2 = this
    #   end
    #
    #   done1 = e1._start()
    #   done2 = e2._start()
    #   begin)
    #     expect(() => done1()).to.raise(/Out-of-order/)
    #   } finally {
    #     done2()
    #     done1()
    #   end
    # end
    #
    # it "should raise a cycle detection error when _start is called while the effect is running" do
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   done = e._start()
    #   begin)
    #     expect(() => e._start()).to.raise(/Cycle detected/)
    #   } finally {
    #     done()
    #   end
    # end
    #
    # it "should dispose the effect on _dispose" do
    #   s = signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   spy = Spy.new {}
    #   e._callback = spy
    #
    #   done = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done()
    #   end
    #   assert_equal(0, spy.called_times)
    #
    #   s.value = 2
    #   expect(spy).to.be.called
    #   spy.reset_history!
    #
    #   e._dispose.call
    #   s.value = 3
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should allow reusing the effect after disposing it" do
    #   s = signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   spy = Spy.new {}
    #   e._callback = spy
    #   e._dispose.call
    #
    #   done = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done()
    #   end
    #   s.value = 2
    #   expect(spy).to.be.called
    # end
    #
    # it "should have property _sources that is undefined when and only when the effect has no sources" do
    #   s = signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #   assert_nil(e._sources)
    #
    #   done1 = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done1()
    #   end
    #   expect(e._sources).not.to.be.undefined
    #
    #   done2 = e._start()
    #   done2()
    #   assert_nil(e._sources)
    #
    #   done3 = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done3()
    #   end
    #   expect(e._sources).not.to.be.undefined
    #
    #   e._dispose.call
    #   assert_nil(e._sources)
    # end
  end

  describe "computed()" do
    it "should return value" do
      a = signal("a")
      b = signal("b")
      c = computed { a.value + b.value }
      assert_equal("ab", c.value)
    end

    it "should return updated value" do
      a = signal("a")
      b = signal("b")

      c = computed { a.value + b.value }
      assert_equal("ab", c.value)

      a.value = "aa"
      assert_equal("aab", c.value)
    end

    it "should conditionally unsubscribe from signals" do
      a = signal("a")
      b = signal("b")
      cond = signal(true)

      spy = Spy.new { cond.value ? a.value : b.value }

      c = computed(&spy)
      assert_equal("a", c.value)
      assert_equal(1, spy.called_times)

      b.value = "bb"
      assert_equal("a", c.value)
      assert_equal(1, spy.called_times)

      cond.value = false
      assert_equal("bb", c.value)
      assert_equal(2, spy.called_times)

      spy.reset_history!

      a.value = "aaa"
      assert_equal("bb", c.value)
      assert_equal(0, spy.called_times)
    end

    it "should consider undefined value from the uninitialized value" do
      # Does this test make any sense? a is not used?
      a = signal(0)
      spy = Spy.new { nil }
      c = computed(&spy)

      assert_nil(c.value)
      a.value = 1
      assert_nil(c.value)
      assert_equal(1, spy.called_times)
    end

    it "should not leak errors raised by dependencies" do
      a = signal(0)
      b =
        computed do
          a.value
          raise
        end
      c =
        computed do
          b.value
        rescue StandardError
          "ok"
        end
      assert_equal("ok", c.value)
      a.value = 1
      assert_equal("ok", c.value)
    end

    it "should propagate notifications even right after first subscription" do
      a = signal(0)
      b = computed { a.value }
      c = computed { b.value }
      c.value

      spy = Spy.new { c.value }

      effect(&spy)
      assert_equal(1, spy.called_times)
      spy.reset_history!

      a.value = 1
      assert_equal(1, spy.called_times)
    end

    it "should get marked as outdated right after first subscription" do
      s = signal(0)
      c = computed { s.value }
      c.value

      s.value = 1
      effect { c.value }
      assert_equal(1, c.value)
    end

    it "should propagate notification to other listeners after one listener is disposed" do
      s = signal(0)
      c = computed { s.value }

      spy1 = Spy.new { c.value }
      spy2 = Spy.new { c.value }
      spy3 = Spy.new { c.value }

      effect(&spy1)
      dispose = effect(&spy2)
      effect(&spy3)

      assert_equal(1, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(1, spy3.called_times)

      dispose.call

      s.value = 1
      assert_equal(2, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(2, spy3.called_times)
    end

    it "should not recompute dependencies out of order" do
      a = signal(1)
      b = signal(1)
      c = signal(1)

      spy = Spy.new { c.value }
      d = computed(&spy)

      e =
        computed do
          if a.value > 0
            b.value
            d.value
          else
            b.value
          end
        end

      e.value
      spy.reset_history!

      a.value = 2
      b.value = 2
      c.value = 2
      e.value
      assert_equal(1, spy.called_times)
      spy.reset_history!

      a.value = -1
      b.value = -1
      c.value = -1
      e.value
      assert_equal(0, spy.called_times)
      spy.reset_history!
    end

    it "should not recompute dependencies unnecessarily" do
      spy = Spy.new {}
      a = signal(0)
      b = signal(0)
      c =
        computed do
          b.value
          spy.call
        end
      d = computed { c.value if a.value.zero? }
      d.value
      assert_equal(1, spy.called_times)

      batch do
        b.value = 1
        a.value = 1
      end
      d.value
      assert_equal(1, spy.called_times)
    end

    describe "peek()" do
      it "should get value" do
        s = signal(1)
        c = computed { s.value }
        assert_equal(1, c.peek)
      end

      it "should refresh value if stale" do
        a = signal(1)
        b = computed { a.value }
        assert_equal(1, b.peek)

        a.value = 2
        assert_equal(2, b.peek)
      end

      it "should detect simple dependency cycles" do
        a = computed { a.peek }
        assert_raises(Signalize::Error) { a.peek }
      end

      it "should detect deep dependency cycles" do
        a = computed { a.value }
        b = computed { c.value }
        c = computed { d.value }
        d = computed { a.peek }
        assert_raises(Signalize::Error) { a.peek }
      end

      it "should not make surrounding effect depend on the computed" do
        s = signal(1)
        c = computed { s.value }
        spy = Spy.new { c.peek }

        effect(&spy)
        assert_equal(1, spy.called_times)

        s.value = 2
        assert_equal(1, spy.called_times)
      end

      it "should not make surrounding computed depend on the computed" do
        s = signal(1)
        c = computed { s.value }

        spy = Spy.new { c.peek() }

        d = computed(&spy)
        d.value
        assert_equal(1, spy.called_times)

        s.value = 2
        d.value
        assert_equal(1, spy.called_times)
      end

      it "should not make surrounding effect depend on the peeked computed's dependencies" do
        a = signal(1)
        b = computed { a.value }
        spy = Spy.new {}
        effect do
          spy.call
          b.peek
        end
        assert_equal(1, spy.called_times)
        spy.reset_history!

        a.value = 1
        assert_equal(0, spy.called_times)
      end

      it "should not make surrounding computed depend on peeked computed's dependencies" do
        a = signal(1)
        b = computed { a.value }
        spy = Spy.new {}
        d =
          computed do
            spy.call
            b.peek
          end
        d.value
        assert_equal(1, spy.called_times)
        spy.reset_history!

        a.value = 1
        d.value
        assert_equal(0, spy.called_times)
      end
    end

    describe "garbage collection" do
      # # Skip GC tests if window.gc/global.gc is not defined.
      # before(function () {
      #   if typeof gc == "undefined"
      #     this.skip()
      #   end
      # end
      #
      # it "should be garbage collectable if nothing is listening to its changes", async  do
      #   s = signal(0)
      #   ref = new WeakRef(computed(() => s.value))
      #
      #   (gc as () => void)()
      #   await new Promise(resolve => setTimeout(resolve, 0))
      #   expect(ref.deref()).to.be.undefined
      # end
      #
      # it "should be garbage collectable after it has lost all of its listeners", async  do
      #   s = signal(0)
      #
      #   ref: WeakRef<Signal>
      #   dispose: () => void
      #   (function () {
      #     c = computed { s.value }
      #     ref = new WeakRef(c)
      #     dispose = effect { c.value }
      #   })()
      #
      #   dispose.call
      #   (gc as () => void)()
      #   await new Promise(resolve => setTimeout(resolve, 0))
      #   expect(ref.deref()).to.be.undefined
      # end
    end

    describe "graph updates" do
      it "should run computeds once for multiple dep changes" do
        a = signal("a")
        b = signal("b")

        compute =
          Spy.new do
            # binding.pry
            a.value + b.value
          end
        c = computed(&compute)

        assert_equal("ab", c.value)
        assert(1, compute.called_times)
        compute.reset_history!

        a.value = "aa"
        b.value = "bb"
        c.value
        assert(1, compute.called_times)
      end

      it "should drop A->B->A updates" do
        #     A
        #   / |
        #  B  | <- Looks like a flag doesn't it? :D
        #   \ |
        #     C
        #     |
        #     D
        a = signal(2)

        b = computed { a.value - 1 }
        c = computed { a.value + b.value }

        compute = Spy.new { "d: #{c.value}" }
        d = computed(&compute)

        # Trigger read
        assert_equal("d: 3", d.value)
        assert(1, compute.called_times)
        compute.reset_history!

        a.value = 4
        d.value
        assert(1, compute.called_times)
      end

      it "should only update every signal once (diamond graph)" do
        # In this scenario "D" should only update once when "A" receives
        # an update. This is sometimes referred to as the "diamond" scenario.
        #     A
        #   /   \
        #  B     C
        #   \   /
        #     D
        a = signal("a")
        b = computed { a.value }
        c = computed { a.value }

        spy = Spy.new { b.value + " " + c.value }
        d = computed(&spy)

        assert_equal("a a", d.value)
        assert_equal(1, spy.called_times)

        a.value = "aa"
        assert_equal("aa aa", d.value)
        assert_equal(2, spy.called_times)
      end

      it "should only update every signal once (diamond graph + tail)" do
        # "E" will be likely updated twice if our mark+sweep logic is buggy.
        #     A
        #   /   \
        #  B     C
        #   \   /
        #     D
        #     |
        #     E
        a = signal("a")
        b = computed { a.value }
        c = computed { a.value }

        d = computed { b.value + " " + c.value }

        spy = Spy.new { d.value }
        e = computed(&spy)

        assert_equal("a a", e.value)
        assert_equal(1, spy.called_times)

        a.value = "aa"
        assert_equal("aa aa", e.value)
        assert_equal(2, spy.called_times)
      end

      it "should bail out if result is the same" do
        # Bail out if value of "B" never changes
        # A->B->C
        a = signal("a")
        b =
          computed do
            a.value
            "foo"
          end

        spy = Spy.new { b.value }
        c = computed(&spy)

        assert_equal("foo", c.value)
        assert_equal(1, spy.called_times)

        a.value = "aa"
        assert_equal("foo", c.value)
        assert_equal(1, spy.called_times)
      end

      # it "should only update every signal once (jagged diamond graph + tails)" do
      #   # "F" and "G" will be likely updated twice if our mark+sweep logic is buggy.
      #   #     A
      #   #   /   \
      #   #  B     C
      #   #  |     |
      #   #  |     D
      #   #   \   /
      #   #     E
      #   #   /   \
      #   #  F     G
      #   a = signal("a")
      #
      #   b = computed { a.value }
      #   c = computed { a.value }
      #
      #   d = computed { c.value }
      #
      #   eSpy = Spy.new { b.value + " " + d.value }
      #   e = computed(eSpy)
      #
      #   fSpy = Spy.new { e.value }
      #   f = computed(fSpy)
      #   gSpy = Spy.new { e.value }
      #   g = computed(gSpy)
      #
      #   assert_equal("a a", f.value)
      #   assert_equal(1, fSpy.called_times)
      #
      #   assert_equal("a a", g.value)
      #   assert_equal(1, gSpy.called_times)
      #
      #   eSpy.reset_history!
      #   fSpy.reset_history!
      #   gSpy.reset_history!
      #
      #   a.value = "b"
      #
      #   assert_equal("b b", e.value)
      #   assert_equal(1, eSpy.called_times)
      #
      #   assert_equal("b b", f.value)
      #   assert_equal(1, fSpy.called_times)
      #
      #   assert_equal("b b", g.value)
      #   assert_equal(1, gSpy.called_times)
      #
      #   eSpy.reset_history!
      #   fSpy.reset_history!
      #   gSpy.reset_history!
      #
      #   a.value = "c"
      #
      #   assert_equal("c c", e.value)
      #   assert_equal(1, eSpy.called_times)
      #
      #   assert_equal("c c", f.value)
      #   assert_equal(1, fSpy.called_times)
      #
      #   assert_equal("c c", g.value)
      #   assert_equal(1, gSpy.called_times)
      #
      #   # top to bottom
      #   expect(eSpy).to.have.been.calledBefore(fSpy)
      #   # left to right
      #   expect(fSpy).to.have.been.calledBefore(gSpy)
      # end

      it "should only subscribe to signals listened to" do
        #    *A
        #   /   \
        # *B     C <- we don't listen to C
        a = signal("a")

        b = computed { a.value }
        spy = Spy.new { a.value }
        computed(&spy)

        assert_equal("a", b.value)
        assert_equal(0, spy.called_times)

        a.value = "aa"
        assert_equal("aa", b.value)
        assert_equal(0, spy.called_times)
      end

      it "should only subscribe to signals listened to" do
        # Here both "B" and "C" are active in the beginning, but
        # "B" becomes inactive later. At that point it should
        # not receive any updates anymore.
        #    *A
        #   /   \
        # *B     D <- we don't listen to C
        #  |
        # *C
        a = signal("a")
        spy_b = Spy.new { a.value }
        b = computed(&spy_b)

        spy_c = Spy.new { b.value }
        c = computed(&spy_c)

        d = computed { a.value }

        result = ""
        unsub = effect { result = c.value }

        assert_equal("a", result)
        assert_equal("a", d.value)

        spy_b.reset_history!
        spy_c.reset_history!
        unsub.call()

        a.value = "aa"

        assert_equal(0, spy_b.called_times)
        assert_equal(0, spy_c.called_times)
        assert_equal("aa", d.value)
      end

      it "should ensure subs update even if one dep unmarks it" do
        # In this scenario "C" always returns the same value. When "A"
        # changes, "B" will update, then "C" at which point its update
        # to "D" will be unmarked. But "D" must still update because
        # "B" marked it. If "D" isn't updated, then we have a bug.
        #     A
        #   /   \
        #  B     *C <- returns same value every time
        #   \   /
        #     D
        a = signal("a")
        b = computed { a.value }
        c =
          computed do
            a.value
            "c"
          end
        spy = Spy.new { b.value + " " + c.value }
        d = computed(&spy)
        assert_equal("a c", d.value)
        spy.reset_history!

        a.value = "aa"
        d.value
        assert_equal("aa c", spy.return_value)
      end

      it "should ensure subs update even if two deps unmark it" do
        # In this scenario both "C" and "D" always return the same
        # value. But "E" must still update because "A"  marked it.
        # If "E" isn't updated, then we have a bug.
        #     A
        #   / | \
        #  B *C *D
        #   \ | /
        #     E
        a = signal("a")
        b = computed { a.value }
        c =
          computed do
            a.value
            "c"
          end
        d =
          computed do
            a.value
            "d"
          end
        spy = Spy.new { b.value + " " + c.value + " " + d.value }
        e = computed(&spy)
        assert_equal("a c d", e.value)
        spy.reset_history!

        a.value = "aa"
        e.value
        assert_equal("aa c d", spy.return_value)
      end
    end
    describe "error handling" do
      it "should raise when writing to computeds" do
        a = signal("a")
        b = computed { a.value }
        assert_raises(NoMethodError) do
          b.value = "aa"
        end
      end

      it "should keep graph consistent on errors during activation" do
        a = signal(0)
        b = computed { raise "fail" }
        c = computed { a.value }
        e = assert_raises(RuntimeError) { b.value }
        assert_equal("fail", e.message)

        a.value = 1
        assert_equal(1, c.value)
      end

      it "should keep graph consistent on errors in computeds" do
        a = signal(0)
        b =
          computed do
            raise "fail" if a.value == 1
            a.value
          end
        c = computed { b.value }
        assert_equal(0, c.value)

        a.value = 1
        e = assert_raises(RuntimeError) { b.value }
        assert_equal("fail", e.message)

        a.value = 2
        assert_equal(2, c.value)
      end

      it "should support lazy branches" do
        a = signal(0)
        b = computed { a.value }
        c = computed { a.value > 0 ? a.value : b.value }

        assert_equal(0, c.value)
        a.value = 1
        assert_equal(1, c.value)

        a.value = 0
        assert_equal(0, c.value)
      end

      it "should not update a sub if all deps unmark it" do
        # In this scenario "B" and "C" always return the same value. When "A"
        # changes, "D" should not update.
        #     A
        #   /   \
        # *B     *C
        #   \   /
        #     D
        a = signal("a")
        b =
          computed do
            a.value
            "b"
          end
        c =
          computed do
            a.value
            "c"
          end
        spy = Spy.new { b.value + " " + c.value }
        d = computed(&spy)
        assert_equal("b c", d.value)
        spy.reset_history!

        a.value = "aa"
        assert_equal(0, spy.called_times)
      end
    end
  end

  describe "batch/transaction" do
    it "should return the value from the callback" do
      assert_equal(1, batch { 1 })
    end

    it "should raise errors raised from the callback" do
      e = assert_raises(RuntimeError) { batch { raise "hello" } }
      assert_equal("hello", e.message)
    end

    # it "should raise non-errors raised from the callback" do
    #   begin
    #     batch do
    #       raise
    #     end
    #     expect.fail()
    #   rescue => err
    #     assert_nil(err)
    #   end
    # end

    it "should delay writes" do
      a = signal("a")
      b = signal("b")
      spy = Spy.new { a.value + " " + b.value }
      effect(&spy)
      spy.reset_history!

      batch do
        a.value = "aa"
        b.value = "bb"
      end

      assert_equal(1, spy.called_times)
    end

    it "should delay writes until outermost batch is complete" do
      a = signal("a")
      b = signal("b")
      spy = Spy.new { a.value + ", " + b.value }
      effect(&spy)
      spy.reset_history!

      batch do
        batch do
          a.value += " inner"
          b.value += " inner"
        end
        a.value += " outer"
        b.value += " outer"
      end

      # If the inner batch) would have flushed the update
      # this spy would've been called twice.
      assert_equal(1, spy.called_times)
    end

    it "should read signals written to" do
      a = signal("a")

      result = ""
      batch do
        a.value = "aa"
        result = a.value
      end

      assert_equal("aa", result)
    end

    it "should read computed signals with updated source signals" do
      # A->B->C->D->E
      a = signal("a")
      b = computed { a.value }

      spy_c = Spy.new { b.value }
      c = computed(&spy_c)

      spy_d = Spy.new { c.value }
      d = computed(&spy_d)

      spy_e = Spy.new { d.value }
      e = computed(&spy_e)

      spy_c.reset_history!
      spy_d.reset_history!
      spy_e.reset_history!

      result = ""
      batch do
        a.value = "aa"
        result = c.value

        # Since "D" isn't accessed during batching, we should not
        # update it, only after batching has completed
        assert_equal(0, spy_d.called_times)
      end

      assert_equal("aa", result)
      assert_equal("aa", d.value)
      assert_equal("aa", e.value)
      assert_equal(1, spy_c.called_times)
      assert_equal(1, spy_d.called_times)
      assert_equal(1, spy_e.called_times)
    end

    it "should not block writes after batching completed" do
      # If no further writes after batch) are possible, than we
      # didn't restore state properly. Most likely "pending" still
      # holds elements that are already processed.
      a = signal("a")
      b = signal("b")
      c = signal("c")
      d = computed { a.value + " " + b.value + " " + c.value }

      result = nil
      effect { result = d.value }

      batch do
        a.value = "aa"
        b.value = "bb"
      end
      c.value = "cc"
      assert_equal("aa bb cc", result)
    end

    it "should not lead to stale signals with .value in batch" do
      invokes = []
      counter = signal(0)
      double = computed { counter.value * 2 }
      triple = computed { counter.value * 3 }

      effect { invokes.push([double.value, triple.value]) }

      assert_equal([[0, 0]], invokes)

      batch do
        counter.value = 1
        assert_equal(2, double.value)
      end

      assert_equal([2, 3], invokes[1])
    end

    it "should not lead to stale signals with peek() in batch" do
      invokes = []
      counter = signal(0)
      double = computed { counter.value * 2 }
      triple = computed { counter.value * 3 }

      effect { invokes.push([double.value, triple.value]) }

      assert_equal([[0, 0]], invokes)

      batch do
        counter.value = 1
        assert_equal(2, double.peek)
      end

      assert_equal([2, 3], invokes[1])
    end

    it "should run pending effects even if the callback raises" do
      a = signal(0)
      b = signal(1)
      spy1 = Spy.new { a.value }
      spy2 = Spy.new { b.value }
      effect(&spy1)
      effect(&spy2)
      spy1.reset_history!
      spy2.reset_history!

      e =
        assert_raises(RuntimeError) do
          batch do
            a.value += 1
            b.value += 1
            raise "hello"
          end
        end

      assert_equal("hello", e.message)

      assert_equal(1, spy1.called_times)
      assert_equal(1, spy2.called_times)
    end

    it "should run pending effects even if some effects raise" do
      a = signal(0)
      spy1 = Spy.new { a.value }
      spy2 = Spy.new { a.value }
      effect { raise "hello" if a.value == 1 }
      effect(&spy1)
      effect { raise "hello" if a.value == 1 }
      effect(&spy2)
      effect { raise "hello" if a.value == 1 }
      spy1.reset_history!
      spy2.reset_history!

      e = assert_raises(RuntimeError) { batch { a.value += 1 } }
      assert_equal("hello", e.message)

      assert_equal(1, spy1.called_times)
      assert_equal(1, spy2.called_times)
    end

    it "should run effect's first run immediately even inside a batch" do
      called_times = 0
      spy = Spy.new {}
      batch do
        effect(&spy)
        called_times = spy.called_times
      end
      assert_equal(1, called_times)
    end
  end
end
