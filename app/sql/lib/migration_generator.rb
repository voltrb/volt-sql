# Run and create migrations programatically.
require 'fileutils'

module Volt
  module Sql
    module MigrationGenerator
      def self.create_migration(name, up_content, down_content)
        timestamp = Time.now.to_i
        file_name = "#{timestamp}_#{name.underscore}"
        class_name = name.camelize
        output_file = "#{Dir.pwd}/config/db/migrations/#{file_name}.rb"

        FileUtils.mkdir_p(File.dirname(output_file))

        content = <<-END.gsub(/^ {8}/, '')
        class #{class_name} < Volt::Migration
          def up
            #{indent_string(up_content, 4)}
          end

          def down
            #{indent_string(down_content, 4)}
          end
        end
        END

        File.open(output_file, 'w') {|f| f.write(content) }

        # return the path to the file
        output_file
      end

      def self.indent_string(string, count)
        string.split("\n").map.with_index do |line,index|
          if index == 0
            string
          else
            (' ' * count) + string
          end
        end.join("\n")
      end
    end
  end
end
