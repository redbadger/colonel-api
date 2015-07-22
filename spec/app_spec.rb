require 'spec_helper'

describe App do
  include Rack::Test::Methods

  def app
    App
  end

  it "says hello" do
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to eq('Hello Colonel')
  end
end
