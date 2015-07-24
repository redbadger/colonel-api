require 'spec_helper'
require 'json'

describe App do
  include Rack::Test::Methods

  def app
    App
  end

  let(:Document) do
    Colonel::DocumentType.new('document') { index_name 'colonel-api' }
  end

  let(:example_blog_1) do
    {
      title: 'Hello Colonel',
      tags: ['Test', 'Content'],
      body: 'Some text.'
    }
  end

  let(:example_blog_2) do
    {
      title: 'Hello Colonel its me again',
      tags: ['Test', 'Content'],
      body: 'Some more text.'
    }
  end

  after do
    client = ::Elasticsearch::Client.new(host: Colonel.config.elasticsearch_uri, log: false)
    client.delete_by_query index: Document.index_name, q: '*'

    # TODO delete redis data
    # redis = Redis.new(host: Rails.configuration.redis_host, port: Rails.configuration.redis_port, password: Rails.configuration.redis_password)
    # storage_keys = redis.keys("rugged:#{Rails.configuration.storage_path}*")
    # redis.del storage_keys unless storage_keys.empty?
    # tag_keys = redis.keys("#{Rails.configuration.tags_key}*")
    # redis.del tag_keys unless tag_keys.empty?
  end

  after { expect(last_response.headers['Content-Type']).to eq 'application/json' }

  it 'GET /documents' do
    doc_1 = Document.new(example_blog_1)
    doc_1.save!(name: 'Erlich Bachman', email: 'erlich@example.com')
    sleep 1
    doc_2 = Document.new(example_blog_2)
    doc_2.save!(name: 'Erlich Bachman', email: 'erlich@example.com')
    sleep 1

    result =
      [
        {
          id: doc_2.id,
          content: doc_2.content
        },
        {
          id: doc_1.id,
          content: doc_1.content
        }
      ]

    get '/documents'
    expect(last_response).to be_ok
    expect(last_response.body).to eq result.to_json
  end

  it 'POST /documents' do
    post_data =
      {
        name: 'Albert Still',
        email: 'albert.still@red-badger.com',
        message: 'Commit message',
        content: example_blog_1
      }

    post '/documents', post_data.to_json

    sleep 1

    response =
      {
        id: Document.list.first.id,
        content: example_blog_1
      }

    expect(last_response).to be_created
    expect(last_response.body).to eq response.to_json
  end

  it 'PUT documents/:id' do
    doc = Document.new(example_blog_1)
    doc.save!({ name: 'Erlich Bachman', email: 'erlich@example.com' }, 'First commit')
    sleep 1
    updated_blog = example_blog_1.clone
    updated_blog[:tags] = ['Test', 'Content', 'Newtag']

    post_data =
      {
        name: 'Albert Still',
        email: 'albert.still@red-badger.com',
        message: 'Commit message',
        content: updated_blog
      }

    put "documents/#{doc.id}", post_data.to_json

    result =
      {
        id: Document.list.first.id,
        content: updated_blog
      }

    expect(last_response).to be_ok
    expect(last_response.body).to eq result.to_json
  end

  it 'GET documents/:id/revisions' do
    doc = Document.new(example_blog_1)
    doc.save!({ name: 'Erlich Bachman', email: 'erlich@example.com' }, 'First commit')
    sleep 1
    doc.content.tags << "Newtag"
    doc.save!({ name: 'Erlich Bachman', email: 'colonel@example.com' }, 'Second commit')
    sleep 1

    get "documents/#{doc.id}/revisions"
    expect(last_response).to be_ok

    updated_blog = example_blog_1.clone
    updated_blog[:tags] = ['Test', 'Content', 'Newtag']
    expect(last_response.body).to eq [updated_blog, example_blog_1].to_json
  end

end
