require "rails_helper"

RSpec.describe "API metrics endpoints", type: :request do
  let(:user_id) { SecureRandom.uuid }

  before { stub_jwks }

  shared_examples "requires authentication" do |path|
    it "returns 401 without a token" do
      get path
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a garbage token" do
      get path, headers: { "Authorization" => "Bearer not-a-jwt" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/metrics/dora" do
    include_examples "requires authentication", "/api/metrics/dora"

    context "authenticated" do
      it "returns 200 with the four DORA keys" do
        get "/api/metrics/dora", headers: auth_headers(user_id)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.keys).to contain_exactly(
          "lead_time_median_seconds", "deployment_frequency",
          "change_failure_rate", "mttr_seconds"
        )
      end

      it "is scoped to the authenticated user" do
        other_user = SecureRandom.uuid
        provider   = create(:llm_provider, user_id: other_user)
        create(:run, :deployed, user_id: other_user, llm_provider: provider)

        get "/api/metrics/dora", headers: auth_headers(user_id)

        body = JSON.parse(response.body)
        expect(body["deployment_frequency"]).to eq({})
      end
    end
  end

  describe "GET /api/metrics/usage" do
    include_examples "requires authentication", "/api/metrics/usage"

    context "authenticated" do
      it "returns 200 with the usage keys" do
        get "/api/metrics/usage", headers: auth_headers(user_id)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.keys).to contain_exactly(
          "run_count", "success_rate", "queue_wait_median_seconds"
        )
      end

      it "is scoped to the authenticated user" do
        other_user = SecureRandom.uuid
        provider   = create(:llm_provider, user_id: other_user)
        create(:run, :succeeded, user_id: other_user, llm_provider: provider)

        get "/api/metrics/usage", headers: auth_headers(user_id)

        expect(JSON.parse(response.body)["run_count"]).to eq(0)
      end
    end
  end

  describe "GET /api/metrics/cost" do
    include_examples "requires authentication", "/api/metrics/cost"

    context "authenticated" do
      it "returns 200 with the cost keys" do
        get "/api/metrics/cost", headers: auth_headers(user_id)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.keys).to contain_exactly(
          "total_usd", "total_tokens", "by_group", "fallback_share"
        )
      end

      it "accepts group_by=provider and returns grouped breakdown" do
        provider = create(:llm_provider, user_id: user_id, provider_name: "openai")
        create(:run, :succeeded, user_id: user_id, llm_provider: provider,
               cost_usd: 2.5, tokens_used: 5_000)

        get "/api/metrics/cost", params: { group_by: "provider" },
                                 headers: auth_headers(user_id)

        groups = JSON.parse(response.body)["by_group"]
        expect(groups.length).to eq(1)
        expect(groups.first["key"]).to eq("openai")
      end

      it "is scoped to the authenticated user" do
        other_user = SecureRandom.uuid
        provider   = create(:llm_provider, user_id: other_user)
        create(:run, :succeeded, user_id: other_user, llm_provider: provider,
               cost_usd: 100.0, tokens_used: 1_000_000)

        get "/api/metrics/cost", headers: auth_headers(user_id)

        expect(JSON.parse(response.body)["total_usd"]).to eq(0.0)
      end
    end
  end

  describe "GET /api/metrics/timeseries" do
    include_examples "requires authentication", "/api/metrics/timeseries"

    context "authenticated" do
      it "returns 200 with metric, interval, and points" do
        get "/api/metrics/timeseries", headers: auth_headers(user_id)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.keys).to contain_exactly("metric", "interval", "points")
        expect(body["metric"]).to eq("run_count")
        expect(body["interval"]).to eq("day")
      end

      it "accepts metric and interval params" do
        get "/api/metrics/timeseries",
            params:  { metric: "cost_usd", interval: "week" },
            headers: auth_headers(user_id)

        body = JSON.parse(response.body)
        expect(body["metric"]).to eq("cost_usd")
        expect(body["interval"]).to eq("week")
      end

      it "is scoped to the authenticated user" do
        other_user = SecureRandom.uuid
        provider   = create(:llm_provider, user_id: other_user)
        create(:run, :succeeded, user_id: other_user, llm_provider: provider)

        get "/api/metrics/timeseries", headers: auth_headers(user_id)

        expect(JSON.parse(response.body)["points"]).to eq([])
      end
    end
  end
end
