# Queries on the client side can be captured using block syntax.  On the client
# a Volt::QueryIdentifier is passed to the block.  It will create a AST for
# queries which is sent.
#
# Sql::WhereCall can reply the query to the underlying database engine (in
# this case, sequel)

module Volt
  module Sql
    class WhereCall
      VALID_METHODS = ['&', '|', '~', '>', '<', '>=', '<=' , '=~', '!~']
      def initialize(ident)
        @ident = ident
      end

      def call(ast)
        walk(ast)
      end

      def walk(ast)
        if ast.is_a?(Array) && !ast.is_a?(Sequel::SQL::Identifier)
          op = ast.shift

          case op
          when 'c'
            return op_call(*ast)
          when 'a'
            # We popped off the 'a', so we just return the array
            return ast
          else
            raise "invalid op: #{op.inspect} - #{ast.inspect} - #{ast.is_a?(Array).inspect}"
          end
        else
          # Not an operation, return
          return ast
        end
      end

      def op_call(self_obj, method_name, *args)
        if self_obj == 'ident'
          self_obj = @ident
        end

        # walk on the self obj
        self_obj = walk(self_obj)

        # Method name security checks
        case method_name
        when 'send'
          raise "Send is not supported in queries"
        end

        if method_name !~ /^[a-zA-Z0-9_]+$/ && !VALID_METHODS.include?(method_name)
          raise "Only method names matching /[a-zA-Z0-9_]/ are allowed from client side queries (called `#{method_name}`)"
        end

        walked_args = args.map {|arg| walk(arg) }

        # We have to use __send__ because send is handled differently
        self_obj.__send__(method_name, *walked_args)
      end
    end
  end
end
