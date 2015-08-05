require 'spec_helper'
require 'json'
require 'redis'

describe App do
  include Rack::Test::Methods

  def app
    App
  end

  let(:example_blog_1) do
    {
      title: 'Hello Colonel',
      tags: %w(Test Content),
      body: 'Some text.'
    }
  end

  let(:example_blog_2) do
    {
      title: 'Hello Colonel its me again',
      tags: %w(Test Content),
      body: 'Some more text.'
    }
  end

  after do
    # clear ES data
    client = Elasticsearch::Client.new(
      host: Colonel.config.elasticsearch_uri,
      log: false)
    client.delete_by_query index: Document.index_name, q: '*'

    # clear Redis data
    Redis.new(host: 'redis', port: 6379).flushdb
  end

  after do
    expect(last_response.headers['Content-Type']).to eq 'application/json'
  end

  it 'GET /documents' do
    doc_1 = Document.new(example_blog_1)
    doc_1.save!(name: 'Erlich Bachman', email: 'erlich@example.com')
    sleep 1
    doc_2 = Document.new(example_blog_2)
    doc_2.save!(name: 'Erlich Bachman', email: 'erlich@example.com')
    sleep 1

    response =
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
    expect(last_response.body).to eq response.to_json
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

  describe 'GET documents/:id' do
    it 'defaults to latest master revision' do
      doc = Document.new(example_blog_1)
      doc.save!(
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'First commit')
      sleep 1
      get "/documents/#{doc.id}"

      response =
        {
          revision_id: doc.revisions['master'].id,
          content: example_blog_1
        }
      expect(last_response).to be_ok
      expect(last_response.body).to eq response.to_json
    end

    it 'gets latest revision from state defined in query param' do
      doc = Document.new(example_blog_1)
      doc.save_in!(
        'foo',
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'First commit')
      sleep 1
      get "/documents/#{doc.id}?state=foo"

      response =
        {
          revision_id: doc.revisions['foo'].id,
          content: example_blog_1
        }
      expect(last_response).to be_ok
      expect(last_response.body).to eq response.to_json
    end
  end

  it 'PUT documents/:id' do
    doc = Document.new(example_blog_1)
    doc.save!(
      { name: 'Erlich Bachman', email: 'erlich@example.com' },
      'First commit')

    sleep 1
    updated_blog = example_blog_1.clone
    updated_blog[:tags] = %w(Test Content Newtag)

    post_data =
      {
        name: 'Albert Still',
        email: 'albert.still@red-badger.com',
        message: 'Commit message',
        content: updated_blog
      }

    put "documents/#{doc.id}", post_data.to_json

    response =
      {
        id: Document.list.first.id,
        content: updated_blog
      }

    expect(last_response).to be_ok
    expect(last_response.body).to eq response.to_json
  end

  it 'POST documents/:id/promote' do
    doc = Document.new(example_blog_1)
    doc.save!(
      { name: 'Erlich Bachman', email: 'erlich@example.com' },
      'First commit')

    publish_commit =
      {
        name: 'Albert Still',
        email: 'oink@farm.com',
        message: 'Published my blog!'
      }

    post "documents/#{doc.id}/promote?from=master&to=foo",
         publish_commit.to_json
    sleep 1
    expect(last_response).to be_ok
    expect(Document.list.first.revisions['foo'].message)
      .to eq 'Published my blog!'
  end

  it 'GET documents/:id/revisions/:id' do
    doc = Document.new(example_blog_1)
    revision = doc.save!(
      { name: 'Erlich Bachman', email: 'erlich@example.com' },
      'First commit')
    sleep 1

    get "documents/#{doc.id}/revisions/#{revision.id}"
    expect(last_response).to be_ok

    response =
      {
        revision_id: revision.id,
        content: revision.content
      }
    expect(last_response.body).to eq response.to_json
  end

  describe 'GET documents/:id/revisions' do
    it 'defaults to latest master revisions' do
      doc = Document.new(example_blog_1)
      revision_1 = doc.save!(
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'First commit')
      sleep 1
      revision_2 = doc.save!(
        { name: 'Erlich Bachman', email: 'colonel@example.com' },
        'Second commit')
      sleep 1

      get "documents/#{doc.id}/revisions"
      expect(last_response).to be_ok

      result =
        [
          {
            revision_id: revision_2.id,
            name: revision_2.author[:name],
            email: revision_2.author[:email],
            message: revision_2.message,
            state: 'master'
          },
          {
            revision_id: revision_1.id,
            name: revision_1.author[:name],
            email: revision_1.author[:email],
            message: revision_1.message,
            state: 'master'
          }
        ]

      expect(last_response.body).to eq result.to_json
    end

    it 'gets revisions from state defined in query param' do
      doc = Document.new(example_blog_1)
      revision_1 = doc.save_in!(
        'foo',
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'First commit')
      sleep 1
      revision_2 = doc.save_in!(
        'foo',
        { name: 'Erlich Bachman', email: 'colonel@example.com' },
        'Second commit')
      sleep 1

      get "documents/#{doc.id}/revisions?state=foo"
      expect(last_response).to be_ok

      result =
        [
          {
            revision_id: revision_2.id,
            name: revision_2.author[:name],
            email: revision_2.author[:email],
            message: revision_2.message,
            state: 'foo'
          },
          {
            revision_id: revision_1.id,
            name: revision_1.author[:name],
            email: revision_1.author[:email],
            message: revision_1.message,
            state: 'foo'
          }
        ]

      expect(last_response.body).to eq result.to_json
    end
  end

  describe 'POST search' do
    it 'should return posts matching the search criteria' do
      doc1 = Document.new(example_blog_1)
      doc1.content = example_blog_1

      doc1.save!(
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'First commit')
      sleep 1

      doc2 = Document.new(example_blog_1)
      doc2.content = example_blog_1
      doc2.content.tags = 'testing'

      doc2.save!(
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'First commit')
      sleep 1

      params = {
        query: {
          constant_score: {
            filter: {
              and: [
                { term: { state: 'master' } },
                { term: { tags: 'testing' } }
              ]
            }
          }
        }
      }

      header = { CONTENT_TYPE: 'application/json', ACCEPT: 'application/json' }
      post 'search', params.to_json, header

      expect(last_response).to be_ok

      result = [
        {
          id: doc2.id,
          content: doc2.content
        }
      ]

      expect(last_response.body).to eq result.to_json
    end
  end

  describe 'GET documents/:id/history' do
    it 'should return history of of a document' do
      doc = Document.new(example_blog_1)
      doc.content = example_blog_1

      revision1 = doc.save!(
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'First commit')
      sleep 1

      revision2 = doc.save!(
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'Second commit')
      sleep 1

      promotion = doc.promote!(
        'master', 'published',
        { name: 'Erlich Bachman', email: 'erlich@example.com' },
        'Published')
      sleep 1

      get "documents/#{doc.id}/history", states: %w(master published)

      expect(last_response).to be_ok

      result = [
        {
          revision_id: promotion.id,
          name: promotion.author[:name],
          email: promotion.author[:email],
          message: promotion.message,
          state: 'published'
        },
        {
          revision_id: revision2.id,
          name: revision2.author[:name],
          email: revision2.author[:email],
          message: revision2.message,
          state: 'master'
        },
        {
          revision_id: revision1.id,
          name: revision1.author[:name],
          email: revision1.author[:email],
          message: revision1.message,
          state: 'master'
        }
      ]

      expect(last_response.body).to eq result.to_json
    end
  end
end
