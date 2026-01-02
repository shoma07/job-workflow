# frozen_string_literal: true

module JobFlow
  # Logger provides structured JSON logging for JobFlow workflows.
  #
  # @example Basic usage
  #   ```ruby
  #   JobFlow.logger = ActiveSupport::Logger.new($stdout)
  #   JobFlow.logger.formatter = JobFlow::Logger::JsonFormatter.new
  #   ```
  #
  # @example With custom log tags
  #   ```ruby
  #   JobFlow.logger.formatter = JobFlow::Logger::JsonFormatter.new(log_tags: [:request_id])
  #   ```
  module Logger
    #:  (ActiveSupport::Logger) -> void
    attr_writer :logger

    #:  () -> ActiveSupport::Logger
    def logger
      @logger ||= build_default_logger
    end

    private

    #:  () -> ActiveSupport::Logger
    def build_default_logger
      logger = ActiveSupport::Logger.new($stdout)
      logger.formatter = Logger::JsonFormatter.new
      logger
    end

    # JSON formatter for structured logging output.
    # @rbs inherits ::Logger::Formatter
    class JsonFormatter < ::Logger::Formatter
      include ActiveSupport::TaggedLogging::Formatter

      #:  (?log_tags: Array[Symbol]) -> void
      def initialize(log_tags: [])
        @log_tags = log_tags
        super()
      end

      #:  (String, Time, String, String | Hash[untyped, untyped]) -> String
      def call(severity, time, progname, msg)
        base_hash = build_base_hash(severity, time, progname)
        tags_hash = build_tags_hash
        msg_hash = build_msg_hash(msg)
        "#{JSON.generate({ **base_hash, **tags_hash, **msg_hash })}\n"
      end

      private

      attr_reader :log_tags #: Array[Symbol]

      #:  (String, Time, String) -> Hash[Symbol, untyped]
      def build_base_hash(severity, time, progname)
        time_in_zone = time.in_time_zone(Time.zone || "UTC")
        { time: time_in_zone.iso8601(6), level: severity, progname: progname }
      end

      #:  () -> Hash[Symbol, untyped]
      def build_tags_hash
        log_tags.zip(current_tags).to_h
      end

      #:  (String | Hash[untyped, untyped]) -> Hash[Symbol, untyped]
      def build_msg_hash(msg)
        case msg
        when Hash
          msg.symbolize_keys
        else
          parse_json_or_message(msg.to_s)
        end
      end

      #:  (String) -> Hash[Symbol, untyped]
      def parse_json_or_message(msg)
        JSON.parse(msg, symbolize_names: true)
      rescue JSON::ParserError
        { message: msg }
      end
    end
  end
end
