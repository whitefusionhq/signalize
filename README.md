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

Signalize's public API consists of four methods (you can think of them almost like functions): `signal`, `computed`, `effect`, and `batch`.

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

### `batch { }`

You can write to  multiple signals within a batch, and flush the updates at all once (thereby notifying computed refreshes and effects).

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

### `peek`

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/rake test` to run the tests, or `bin/guard` or run them continuously in watch mode. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Signalize is considered a direct port of the [original Signals JavaScript library](https://github.com/preactjs/signals). This means we are unlikely to accept any additional features other than what's provided by Signals. If Signals adds new functionality in the future, we will endeavor to replicate it in Signalize. Furthermore, if there's some unwanted behavior in Signalize that's also present in Signals, we are unlikely to modify that behavior.

However, if you're able to supply a bugfix or performance optimization which will help bring Signalize _more_ into alignment with its Signals counterpart, we will gladly accept your PR!

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/whitefusionhq/signalize/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Signalize project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/whitefusionhq/signalize/blob/main/CODE_OF_CONDUCT.md).
