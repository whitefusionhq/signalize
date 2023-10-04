# Signalize

Signalize is a Ruby port of the JavaScript-based [core Signals package](https://github.com/preactjs/signals) by the Preact project. Signals provides reactive variables, derived computed state, side effect callbacks, and batched updates.

Additional context as provided by the original documentation:

> Signals is a performant state management library with two primary goals:
> 
> Make it as easy as possible to write business logic for small up to complex apps. No matter how complex your logic is, your app updates should stay fast without you needing to think about it. Signals automatically optimize state updates behind the scenes to trigger the fewest updates necessary. They are lazy by default and automatically skip signals that no one listens to.
> Integrate into frameworks as if they were native built-in primitives. You don't need any selectors, wrapper functions, or anything else. Signals can be accessed directly and your component will automatically re-render when the signal's value changes.

While a lot of what we tend to write in Ruby is in the form of repeated, linear processing cycles (aka HTTP requests/responses on the web), there is increasingly a sense that we can look at concepts which make a lot of sense on the web frontend in the context of UI interactions and data flows and apply similar principles to the backend as well. Signalize helps you do just that.

**NOTE:** read the Contributing section below before submitting a bug report or PR.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add signalize

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install signalize

## Usage

Signalize's public API consists of five methods (you can think of them almost like functions): `signal`, `untracked`, `computed`, `effect`, and `batch`.

### `signal(initial_value)`

The first building block is the `Signalize::Signal` class. You can think of this as a reactive value object which wraps an underlying primitive like String, Integer, Array, etc.

```ruby
require "signalize"

counter = Signalize.signal(0)

# Read value from signal, logs: 0
puts counter.value

# Write to a signal
counter.value = 1
```

You can include the `Signalize::API` mixin to access these methods directly in any context:

```ruby
require "signalize"
include Signalize::API

counter = signal(0)

counter.value += 1
```

### `untracked { }`

In case when you're receiving a callback that can read some signals, but you don't want to subscribe to them, you can use `untracked` to prevent any subscriptions from happening.

```ruby
require "signalize"
include Signalize::API

counter = signal(0)
effect_count = signal(0)
fn = proc { effect_count.value + 1 }

effect do
  # Logs the value
	puts counter.value

	# Whenever this effect is triggered, run `fn` that gives new value
	effect_count.value = untracked(&fn)
end
```

### `computed { }`

You derive computed state by accessing a signal's value within a `computed` block and returning a new value. Every time that signal value is updated, a computed value will likewise be updated. Actually, that's not quite accurate — the computed value only computes when it's read. In this sense, we can call computed values "lazily-evaluated".

```ruby
require "signalize"
include Signalize::API

name = signal("Jane")
surname = signal("Doe")

full_name = computed do
  name.value + " " + surname.value
end

# Logs: "Jane Doe"
puts full_name.value

name.value = "John"
name.value = "Johannes"
# name.value = "..."
# Setting value multiple times won't trigger a computed value refresh

# NOW we get a refreshed computed value:
puts full_name.value
```

### `effect { }`

Effects are callbacks which are executed whenever values which the effect has "subscribed" to by referencing them have changed. An effect callback is run immediately when defined, and then again for any future mutations.

```ruby
require "signalize"
include Signalize::API

name = signal("Jane")
surname = signal("Doe")
full_name = computed { name.value + " " + surname.value }

# Logs: "Jane Doe"
effect { puts full_name.value }

# Updating one of its dependencies will automatically trigger
# the effect above, and will print "John Doe" to the console.
name.value = "John"
```

You can dispose of an effect whenever you want, thereby unsubscribing it from signal notifications.

```ruby
require "signalize"
include Signalize::API

name = signal("Jane")
surname = signal("Doe")
full_name = computed { name.value + " " + surname.value }

# Logs: "Jane Doe"
dispose = effect { puts full_name.value }

# Destroy effect and subscriptions
dispose.()

# Update does nothing, because no one is subscribed anymore.
# Even the computed `full_name` signal won't change, because it knows
# that no one listens to it.
surname.value = "Doe 2"
```

**IMPORTANT:** you cannot use `return` or `break` within an effect block. Doing so will raise an exception (due to it breaking the underlying execution model).

```ruby
def my_method(signal_obj)
  effect do
    return if signal_obj.value > 5 # DON'T DO THIS!

    puts signal_obj.value
  end

  # more code here
end
```

Instead, try to resolve it using more explicit logic:

```ruby
def my_method(signal_obj)
  should_exit = false

  effect do
    should_exit = true && next if signal_obj.value > 5

    puts signal_obj.value
  end

  return if should_exit

  # more code here
end
```

However, there's no issue if you pass in a method proc directly:

```ruby
def my_method(signal_obj)
  @signal_obj = signal_obj

  effect &method(:an_effect_method)

  # more code here
end

def an_effect_method
  return if @signal_obj.value > 5

  puts @signal_obj.value
end
```

### `batch { }`

You can write to multiple signals within a batch, and flush the updates at all once (thereby notifying computed refreshes and effects).

```ruby
require "signalize"
include Signalize::API

name = signal("Jane")
surname = signal("Doe")
full_name = computed { name.value + " " + surname.value }

# Logs: "Jane Doe"
dispose = effect { puts full_name.value }

batch do
  name.value = "Foo"
  surname.value = "Bar"
end
```

### `signal.subscribe { }`

You can explicitly subscribe to a signal signal value and be notified on every change. (Essentially the Observable pattern.) In your block, the new signal value will be supplied as an argument.

```ruby
require "signalize"
include Signalize::API

counter = signal(0)

counter.subscribe do |new_value|
  puts "The new value is #{new_value}"
end

counter.value = 1 # logs the new value
```

### `signal.peek`

If you need to access a signal's value inside an effect without subscribing to that signal's updates, use the `peek` method instead of `value`.

```ruby
require "signalize"
include Signalize::API

counter = signal(0)
effect_count = signal(0)

effect do
  puts counter.value

  # Whenever this effect is triggered, increase `effect_count`.
  # But we don't want this signal to react to `effect_count`
  effect_count.value = effect_count.peek + 1
end
```

## Signalize Struct

An optional add-on to Signalize, the `Singalize::Struct` class lets you define multiple signal or computed variables to hold in struct-like objects. You can even add custom methods to your classes with a simple DSL. (The API is intentionally similar to `Data` in Ruby 3.2+, although these objects are of course mutable.)

Here's what it looks like:

```ruby
require "signalize/struct"

include Signalize::API

TestSignalsStruct = Signalize::Struct.define(
  :str,
  :int,
  :multiplied_by_10
) do # optional block for adding methods
  def increment!
    self.int += 1
  end
end

struct = TestSignalsStruct.new(
  int: 0,
  str: "Hello World",
  multiplied_by_10: computed { struct.int * 10 }
)

effect do
  puts struct.multiplied_by_10 # 0
end

effect do
  puts struct.str # "Hello World"
end

struct.increment! # above effect will now output 10
struct.str = "Goodbye!" # above effect will now output "Goodbye!"
```

If you ever need to get at the actual `Signal` object underlying a value, just call `*_signal`. For example, you could call `int_signal` for the above example to get a signal object for `int`.

Signalize structs require all of their members to be present when initializing…you can't pass only some keyword arguments.

Signalize structs support `to_h` as well as `deconstruct_keys` which is used for pattern matching and syntax like `struct => { str: }` to set local variables.

You can call `members` (as both object/class methods) to get a list of the value names in the struct.

Finally, both `inspect` and `to_s` let you debug the contents of a struct.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/rake test` to run the tests, or `bin/guard` or run them continuously in watch mode. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Signalize is considered a direct port of the [original Signals JavaScript library](https://github.com/preactjs/signals). This means we are unlikely to accept any additional features other than what's provided by Signals (unless it's completely separate, like our `Signalize::Struct` add-on). If Signals adds new functionality in the future, we will endeavor to replicate it in Signalize. Furthermore, if there's some unwanted behavior in Signalize that's also present in Signals, we are unlikely to modify that behavior.

However, if you're able to supply a bugfix or performance optimization which will help bring Signalize _more_ into alignment with its Signals counterpart, we will gladly accept your PR!

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/whitefusionhq/signalize/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
