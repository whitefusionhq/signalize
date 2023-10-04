# frozen_string_literal: true

require "test_helper"
require "signalize/struct"

class TestStruct < Minitest::Test
  include Signalize::API

  TestSignalsStruct = Signalize::Struct.define(
    :str,
    :int
  ) do
    def increment!
      self.int += 1
    end
  end

  def test_int_value
    struct = TestSignalsStruct.new(int: 0, str: "")

    assert_equal 0, struct.int
    assert_equal 0, struct.int_signal.value
    
    # Write to a signal
    struct.int = 1

    assert_equal 1, struct.int

    struct.increment!

    assert_equal 2, struct.int
  end

  def test_str_computed
    struct = TestSignalsStruct.new(str: "Doe", int: 0)
    name = signal("Jane")

    computed_ran_once = 0
    
    full_name = computed do
      computed_ran_once += 1
      name.value + " " + struct.str
    end

    assert_equal "Jane Doe", full_name.value
    
    name.value = "John"
    name.value = "Johannes"
    # name.value = "..."
    # Setting value multiple times won't trigger a computed value refresh
    
    # NOW we get a refreshed computed value:
    assert_equal "Johannes Doe", full_name.value
    assert_equal 2, computed_ran_once

    # Test deconstructing
    struct => { str: }
    assert_equal "Doe", str
  end
end
