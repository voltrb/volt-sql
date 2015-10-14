module Volt
  module Sql
    module SqlLogger

      def log(msg)
        unless ENV['QUIET_SQL']
          Volt.logger.log_with_color(msg, :cyan)
        end
      end

    end
  end
end
