describe "Swagger stuff" do
  let(:rails_routes) do
    Rails.application.routes.routes.each_with_object([]) do |route, array|
      r = ActionDispatch::Routing::RouteWrapper.new(route)
      next if r.internal? # Don't display rails routes
      next if r.engine? # Don't care right now...

      array << {:verb => r.verb, :path => r.path.split("(").first.sub(/:[_a-z]*id/, ":id")}
    end
  end

  let(:swagger_routes) { Api::Docs.routes }

  describe "Routing" do
    include Rails.application.routes.url_helpers

    before do
      stub_const("ENV", ENV.to_h.merge("PATH_PREFIX" => path_prefix, "APP_NAME" => app_name))
      Rails.application.reload_routes!
    end

    after(:all) do
      Rails.application.reload_routes!
    end

    context "with the swagger yaml" do
      let(:app_name)    { "sources" }
      let(:path_prefix) { "/r/insights/platform" }

      it "matches the routes" do
        redirect_routes = [{:path => "#{path_prefix}/#{app_name}/v0/*path", :verb => "DELETE|GET|OPTIONS|PATCH|POST"}]
        internal_api_routes = [{:path => "/internal/v0/*path", :verb => "GET"}, {:path=>"/internal/v0.1/authentications/:id", :verb=>"GET"}]
        expect(rails_routes).to match_array(swagger_routes + redirect_routes + internal_api_routes)
      end
    end

    context "customizable route prefixes" do
      let(:path_prefix) { random_path }
      let(:app_name)    { random_path_part }

      it "with a random prefix" do
        expect(ENV["PATH_PREFIX"]).not_to be_nil
        expect(ENV["APP_NAME"]).not_to be_nil
        expect(api_v0x1_sources_url(:only_path => true)).to eq("/#{URI.encode(ENV["PATH_PREFIX"])}/#{URI.encode(ENV["APP_NAME"])}/v0.1/sources")
      end

      it "with extra slashes" do
        ENV["PATH_PREFIX"] = "//example/path/prefix/"
        ENV["APP_NAME"] = "/appname/"
        Rails.application.reload_routes!

        expect(api_v0x1_sources_url(:only_path => true)).to eq("/example/path/prefix/appname/v0.1/sources")
      end

      it "doesn't use the APP_NAME when PATH_PREFIX is empty" do
        ENV["PATH_PREFIX"] = ""
        Rails.application.reload_routes!

        expect(ENV["APP_NAME"]).not_to be_nil
        expect(api_v0x1_sources_url(:only_path => true)).to eq("/api/v0.1/sources")
      end
    end

    def words
      @words ||= File.readlines("/usr/share/dict/words").collect(&:strip)
    end

    def random_path_part
      rand(1..5).times.collect { words.sample }.join("_")
    end

    def random_path
      rand(1..10).times.collect { random_path_part }.join("/")
    end
  end

  describe "Model serialization" do
    let(:doc) { Api::Docs[version] }
    let(:authentication) { Authentication.create!(doc.example_attributes("Authentication").symbolize_keys.merge(:tenant => tenant, :resource => endpoint)) }
    let(:endpoint) { Endpoint.create!(doc.example_attributes("Endpoint").symbolize_keys.merge(:tenant => tenant, :source => source)) }
    let(:source) { Source.create!(doc.example_attributes("Source").symbolize_keys.merge(:source_type => source_type, :tenant => tenant, :uid => SecureRandom.uuid)) }
    let(:source_type) { SourceType.create!(:name => "openshift", :product_name => "OpenShift", :vendor => "Red Hat") }
    let(:tenant) { Tenant.create!(:external_tenant => SecureRandom.uuid) }

    context "v0.1" do
      let(:version) { "0.1" }
      Api::Docs["0.1"].definitions.each do |definition_name, schema|
        next if definition_name.in?(["CollectionLinks", "CollectionMetadata", "OrderParameters", "Tagging"])
        definition_name = definition_name.sub(/Collection\z/, "").singularize

        it "#{definition_name} matches the JSONSchema" do
          const = definition_name.constantize
          expect(send(definition_name.underscore).as_json(:prefixes => ["api/v0x1/#{definition_name.underscore}"])).to match_json_schema("0.1", definition_name)
        end
      end
    end
  end
end
