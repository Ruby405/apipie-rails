# Restapi DSL functions.

module Restapi

  # DSL is a module that provides #api, #error, #param, #error.  Use this
  # when you'd like to use restapi outside the top level scope.

  module DSL

    private

    # Declare an api.
    #
    # Example:
    #   api :desc => "short description",
    #       :path => "/resource_route",
    #       :method => "GET"
    #
    def api(args)
      Restapi.last_api_args = args
    end

    # Describe the next method.
    #
    # Example:
    #   desc "print hello world"
    #   def hello_world
    #     puts "hello world"
    #   end
    #
    def desc(description)
      if Restapi.last_description
        raise "Double method description."
      end
      Restapi.last_description = description
    end

    # Describe possible errors
    #
    # Example:
    #   error :desc => "speaker is sleeping", :code => 500
    #   def hello_world
    #     return 500 if self.speaker.sleeping?
    #     puts "hello world"
    #   end
    #
    def error(args)
      Restapi.last_errors << Restapi::ErrorDescription.new(args)
    end
    
    # Describe method's parameter
    #
    # Example:
    #   param :greeting, String, :desc => "arbitrary text", :required => true
    #   def hello_world(greeting)
    #     puts greeting
    #   end
    #
    def param(param_name, *args, &block)
      Restapi.last_params[param_name.to_sym] = Restapi::ParamDescription.new(param_name, *args, &block)
    end
    
    # create method api and redefine newly added method
    def method_added(method_name)

      super
      
      return unless Restapi.restapi_provided?
      
      method_name = method_name.to_sym
      resource_name = self.controller_name

      # remove mapi if exists and create new one
      Restapi.remove_method_description(resource_name, method_name)
      mapi = Restapi.define_method_description(resource_name, method_name)

      # redefine method
      old_method = instance_method(method_name) 
  
      define_method(method_name) do |*args|
        
        mapi.params.each do |_, param|

          # check if required parameters are present
          if param.required && !params.has_key?(param.name)
            raise ArgumentError.new("Expecting #{param.name} parameter.")
          end
          
          # params validations
          if params.has_key?(param.name)
            param.validate(params[:"#{param.name}"])
          end

        end # params.each

        # run the original method code
        old_method.bind(self).call(*args)

      end
      
    end # def method_added
  end # module DSL
end # module Restapi