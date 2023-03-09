# frozen_string_literal: true

require "test_helper"

class TestSignalize < Minitest::Test
  include Signalize::API

  def test_that_it_has_a_version_number
    refute_nil ::Signalize::VERSION
  end

  def test_it_does_something_useful
    processing = ProcessingTester.new

    computed_ran_once = 0

    words_array = computed do
      computed_ran_once += 1
      processing.results.map { in_words(_1) }.freeze
    end

    effect do
      # Computed variables are lazily evalutated, that is, they don't compute until
      # their `.value` is read. But if we add the following statement, every effect
      # run will force a computation:
      #
      # puts "in an effect! #{words_array.value}"

      processing.stop if processing.results.length > 5
    end

    processing.process

    assert_equal 0, computed_ran_once
    assert_equal "one, two, three, four, five, six", words_array.value.join(", ")
    assert_equal 1, computed_ran_once
  end

  def test_basic_signal
    counter = signal(0)

    # Read value from signal, logs: 0
    assert_equal 0, counter.value
    
    # Write to a signal
    counter.value = 1

    assert_equal 1, counter.value
    assert_equal 1, counter.peek
  end

  def test_computed
    name = signal("Jane")
    surname = signal("Doe")

    computed_ran_once = 0
    
    full_name = computed do
      computed_ran_once += 1
      name.value + " " + surname.value
    end

    assert_equal "Jane Doe", full_name.value
    
    name.value = "John"
    name.value = "Johannes"
    # name.value = "..."
    # Setting value multiple times won't trigger a computed value refresh
    
    # NOW we get a refreshed computed value:
    assert_equal "Johannes Doe", full_name.value
    assert_equal 2, computed_ran_once
  end

  def test_effect
    name = signal("Jane")
    surname = signal("Doe")
    full_name = computed { name.value + " " + surname.value }

    effect_ran_twice = 0
    effect_output = ""

    dispose = effect do
      effect_output = full_name.value
      effect_ran_twice += 1
    end
    
    # Updating one of its dependencies will automatically trigger
    # the effect above, and will print "John Doe" to the console.
    name.value = "John"

    assert_equal "John Doe", effect_output
    assert_equal 2, effect_ran_twice

    dispose.()

    name.value = "Jack"
    assert_equal 2, effect_ran_twice
  end

  def multiple_effect_run
    x = Signalize.signal(1)
    results = nil
    Signalize.effect do
      results = "done" if x.value == 3
    end; x.value = 2; x.value = 3; x.value = 4
    results || "oops"
  end

  def test_multiple_runs
    multiple_effect_run

    assert_equal "done", multiple_effect_run
  end

  def test_batch
    name = signal("Jane")
    surname = signal("Doe")
    full_name = computed { name.value + " " + surname.value }

    effect_output = ""
    effect_ran_twice = 0

    effect do
      effect_output = full_name.value
      effect_ran_twice += 1
    end

    batch do
      name.value = "Foo"
      surname.value = "Bar"
    end

    assert_equal "Foo Bar", effect_output
    assert_equal 2, effect_ran_twice
  end

  def test_subscribe
    test_value = 0
    counter = signal(test_value)

    counter.subscribe do |new_value|
      assert_equal test_value, new_value
    end

    test_value = 10
    counter.value = test_value # logs the new value
  end
end
