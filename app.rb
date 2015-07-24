require 'sinatra/base'
require 'colonel'
require 'rugged-redis'
require 'pry'
require 'json'

Colonel.config.elasticsearch_uri = 'elasticsearch:9200'

redis_backend = Rugged::Redis::Backend.new(host: 'redis', port: 6379)
Colonel.config.rugged_backend = redis_backend

Document = Colonel::DocumentType.new('document') { index_name 'colonel-api' }

Colonel::ElasticsearchProvider.initialize!

# The API
class App < Sinatra::Base
  set :bind, '0.0.0.0'

  before do
    content_type 'application/json'
  end

  get '/documents' do
    Document.list(sort: { updated_at: 'desc' }).map do |doc|
      doc_hash(doc)
    end.to_json
  end

  post '/documents' do
    data = JSON.parse(request.body.read)
    doc = Document.new(data['content'])
    doc.save!({ name: data['name'], email: data['email'] }, data['message'])

    status 201
    body doc_hash(doc).to_json
  end

  put '/documents/:id' do |id|
    doc = Document.open(id)
    data = JSON.parse(request.body.read)
    doc.content = data['content']
    doc.save!({ name: data['name'], email: data['email'] }, data['message'])

    status 200
    body doc_hash(doc).to_json
  end

  get '/documents/:id/revisions' do |id|
    Document.open(id).history.map(&:content).to_json
  end

  private

  def doc_hash(doc)
    {
      id: doc.id,
      content: doc.content
    }
  end

  run! if app_file == $0
end
