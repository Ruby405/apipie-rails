require 'apipie/static_dispatcher'
require 'yaml'

module Apipie

  class Application

    # we need engine just for serving static assets
    class Engine < Rails::Engine
      initializer "static assets" do |app|
        app.middleware.use ::Apipie::StaticDispatcher, "#{root}/app/public", Apipie.configuration.doc_base_url
      end
    end

    attr_accessor :last_api_args, :last_errors, :last_params, :last_description,
                  :last_examples, :last_see, :last_formats, :last_api_versions
    attr_reader :resource_descriptions

    def initialize
      super
      init_env
      clear_last
    end

    def available_versions
      @resource_descriptions.keys.sort
    end

    def set_resource_id(controller, resource_id)
      @controller_to_resource_id[controller] = resource_id
    end

    # create new method api description
    def define_method_description(controller, method_name, versions = [])
      return if ignored?(controller, method_name)
      ret_method_description = nil

      versions = controller_versions(controller) if versions.empty?

      versions.each do |version|
        resource_name_with_version = "#{version}##{get_resource_name(controller)}"
        resource_description = get_resource_description(resource_name_with_version)

        if resource_description.nil?
          resource_description = define_resource_description(controller, version)
        end

        method_description = Apipie::MethodDescription.new(method_name, resource_description, self)

        # we create separate method description for each version in
        # case the method belongs to more versions. We return just one
        # becuase the version doesn't matter for the purpose it's used
        # (to wrap the original version with validators)
        ret_method_description ||= method_description
        resource_description.add_method_description(method_description)
      end

      return ret_method_description
    end

    # create new resource api description
    def define_resource_description(controller, version, &block)
      return if ignored?(controller)

      resource_name = get_resource_name(controller)
      resource_description = @resource_descriptions[version][resource_name]
      if resource_description
        # we already defined the description somewhere (probably in
        # some method. Updating just the description
        resource_description.eval_resource_description(&block) if block_given?
      else
        resource_description = Apipie::ResourceDescription.new(controller, resource_name, version, &block)

        Apipie.debug("@resource_descriptions[#{version}][#{resource_name}] = #{resource_description}")
        @resource_descriptions[version][resource_name] ||= resource_description
      end

      return resource_description
    end

    # what versions is the resource defined for?
    def get_resource_versions(controller, &block)
      ret = Apipie::ResourceDescription::VersionsExtractor.versions(&block)
      if ret.empty?
        ret = controller_versions(controller.superclass)
      end
      return ret
    end

    # recursively searches what versions has the controller specified in
    # resource_description? It's used to derivate the default value of
    # versions for methods.
    def controller_versions(controller)
      ret = @controller_versions[controller]
      return ret unless ret.empty?
      if controller == ActionController::Base || controller.nil?
        return [Apipie.configuration.default_version]
      else
        return controller_versions(controller.superclass)
      end
    end

    def set_controller_versions(controller, versions)
      @controller_versions[controller] = versions
    end

    def add_method_description_args(method, path, desc)
      @last_api_args << MethodDescription::Api.new(method, path, desc)
    end

    def add_example(example)
      @last_examples << example.strip_heredoc
    end

    # check if there is some saved description
    def apipie_provided?
      true unless last_api_args.blank?
    end

    # get api for given method
    #
    # There are two ways how this method can be used:
    # 1) Specify both parameters
    #   resource_name:
    #       controller class - UsersController
    #       string with resource name (plural) and version - "v1#users"
    #   method_name: name of the method (string or symbol)
    #
    # 2) Specify only first parameter:
    #   resource_name: string containing both resource and method name joined
    #   with '#' symbol.
    #   - "users#create" get default version
    #   - "v2#users#create" get specific version
    def get_method_description(resource_name, method_name = nil)
      if resource_name.is_a?(String)
        crumbs = resource_name.split('#')
        if crumbs.size == 2
          resource_description = get_resource_description(resource_name)
        elsif crumbs.size == 3
          method_name = crumbs.pop
          resource_description = get_resource_description(crumbs.join('#'))
        end
      elsif resource_name.respond_to? :apipie_resource_descriptions
        resource_description = get_resource_description(resource_name)
      else
        raise ArgumentError.new("Resource #{resource_name} does not exists.")
      end
      unless resource_description.nil?
        resource_description._methods[method_name.to_sym]
      end
    end
    alias :[] :get_method_description

    # options:
    # => "users"
    # => "v2#users"
    # =>  V2::UsersController
    def get_resource_description(resource, version = nil)
      if resource.is_a?(String)
        crumbs = resource.split('#')
        if crumbs.size == 1
          @resource_descriptions[Apipie.configuration.default_version][resource]
        elsif crumbs.size == 2 && @resource_descriptions.has_key?(crumbs.first)
          @resource_descriptions[crumbs.first][crumbs.last]
        end
      elsif resource.respond_to?(:apipie_resource_descriptions)
        return nil if resource == ActionController::Base
        return nil unless resource.apipie_resource_descriptions
        version ||= Apipie.configuration.default_version
        resource.apipie_resource_descriptions.find do |r|
          r._version == version
        end
      end
    end

    def remove_method_description(resource, versions, method_name)
      versions.each do |version|
        resource = get_resource_name(resource)
        resource_description = get_resource_description("#{version}##{resource}")
        if resource_description && resource_description._methods.has_key?(method_name)
          resource_description._methods.delete method_name
        end
      end
    end

    # initialize variables for gathering dsl data
    def init_env
      @resource_descriptions = HashWithIndifferentAccess.new { |h, version| h[version] = {} }
      @controller_to_resource_id = {}

      # what versions does the controller belong in (specified by resource_description)?
      @controller_versions = Hash.new { |h, controller| h[controller] = [] }
    end
    # clear all saved data
    def clear_last
      @last_api_args = []
      @last_errors = []
      @last_params = []
      @last_description = nil
      @last_examples = []
      @last_see = nil
      @last_formats = nil
      @last_api_versions = []
    end

    # Return the current description, clearing it in the process.
    def get_description
      desc = @last_description
      @last_description = nil
      desc
    end

    def get_errors
      @last_errors.clone
    end

    def get_api_args
      @last_api_args.clone
    end

    def get_see
      @last_see
    end

    def get_formats
      @last_formats
    end

    def get_params
      @last_params.clone
    end

    def get_examples
      @last_examples.clone
    end

    def recorded_examples
      return @recorded_examples if @recorded_examples
      tape_file = File.join(Rails.root,"doc","apipie_examples.yml")
      if File.exists?(tape_file)
        @recorded_examples = YAML.load_file(tape_file)
      else
        @recorded_examples = {}
      end
      @recorded_examples
    end

    def reload_examples
      @recorded_examples = nil
    end

    def to_json(version, resource_name, method_name)

      _resources = if resource_name.blank?
        # take just resources which have some methods because
        # we dont want to show eg ApplicationController as resource
        resource_descriptions[version].inject({}) do |result, (k,v)|
          result[k] = v.to_json unless v._methods.blank?
          result
        end
      else
        [@resource_descriptions[version][resource_name].to_json(method_name)]
      end

      url_args = Apipie.configuration.version_in_url ? version : ''

      {
        :docs => {
          :name => Apipie.configuration.app_name,
          :info => Apipie.app_info(version),
          :copyright => Apipie.configuration.copyright,
          :doc_url => Apipie.full_url(url_args),
          :api_url => Apipie.api_base_url(version),
          :resources => _resources
        }
      }
    end

    def api_controllers_paths
      Dir[Apipie.configuration.api_controllers_matcher]
    end

    def reload_documentation
      rails_mark_classes_for_reload
      init_env
      reload_examples

      api_controllers_paths.each do |f|
        load_controller_from_file f
      end
    end

    # Is there a reason to interpret the DSL for this run?
    # with specific setting for some environment there is no reason the dsl
    # should be interpreted (e.g. no validations and doc from cache)
    def active_dsl?
      Apipie.configuration.validate? || ! Apipie.configuration.use_cache? || Apipie.configuration.force_dsl?
    end

    private

    def get_resource_name(klass)
      if klass.class == String
        klass
      elsif @controller_to_resource_id.has_key?(klass)
        @controller_to_resource_id[klass]
      elsif klass.respond_to?(:controller_name)
        return nil if klass == ActionController::Base
        klass.controller_name
      else
        raise "Apipie: Can not resolve resource #{klass} name."
      end
    end

    def get_resource_version(resource_description)
      if resource_description.respond_to? :_version
        resource_description._version
      else
        Apipie.configuration.default_version
      end
    end

    def load_controller_from_file(controller_file)
      controller_class_name = controller_file.gsub(/\A.*\/app\/controllers\//,"").gsub(/\.\w*\Z/,"").camelize
      controller_class_name.constantize
    end

    def ignored?(controller, method = nil)
      ignored = Apipie.configuration.ignored
      return true if ignored.include?(controller.name)
      return true if ignored.include?("#{controller.name}##{method}")
    end

    # Since Rails 3.2, the classes are reloaded only on file change.
    # We need to reload all the controller classes to rebuild the
    # docs, therefore we just force to reload all the code. This
    # happens only when reload_controllers is set to true and only
    # when showing the documentation.
    def rails_mark_classes_for_reload
      ActiveSupport::DescendantsTracker.clear
      ActiveSupport::Dependencies.clear
    end

  end
end
