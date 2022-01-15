# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

unless defined?(Minitest::Test)
  Minitest::Test = MiniTest::Unit::TestCase
end

# Set up a watcher for leaking agent threads out of tests.  It'd be nice to
# disable the threads everywhere, but not all tests have newrelic.yml loaded to
# us to rely on, so instead we'll just watch for it.
class Minitest::Test
  def before_setup
    if self.respond_to?(:name)
      test_method_name = self.name
    else
      test_method_name = self.__name__
    end

    NewRelic::Agent.logger.info("*** #{self.class}##{test_method_name} **")
    setup_thread_tracking

    super
  end

  def setup_thread_tracking
    set_threads = Proc.new do
      @__thread_count = ruby_threads.count
      @__threads = ruby_threads.map { |rt| Hometown.for(rt).backtrace[0] }
    end

    # Rails 7 changes when active record loads and the threads get created.
    # In order to keep the thread count consistent we need to wrap it in Rails.application.executor.wrap on rails 7+
    if defined?(Rails) && Gem::Version.new(::Rails::VERSION::STRING) >= Gem::Version.new('7.0.0')
      Rails.application.executor.wrap do
        set_threads.call
      end
    else
      set_threads.call
    end
  end

  def after_teardown
    nr_unfreeze_time
    nr_unfreeze_process_time

    threads = ruby_threads
    if @__thread_count != threads.count
      puts "", "=" * 80, "originally: #{@__threads.inspect}", "=" * 80
      backtraces = threads.map do |thread|
        trace = Hometown.for(thread)
        trace.backtrace.join("\n    ")
      end.join("\n\n")

      fail "Thread count changed in this test from #{@__thread_count} to #{threads.count}\n#{backtraces}"
    end

    super
  end

  # We only want to count threads that were spun up from Ruby (i.e.
  # Thread.new) JRuby has system threads we don't care to track.
  def ruby_threads
    Thread.list.select { |t| Hometown.for(t) }
  end
end
