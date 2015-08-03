require 'sinatra/base'
require 'colonel'
require 'rugged-redis'
require 'pry'
require 'json'

uri = URI(ENV['ELASTICSEARCH_URI'] || ENV['COLONELAPI_ELASTICSEARCH_1_PORT'])
uri.scheme = 'http' # is tcp otherwise
Colonel.config.elasticsearch_uri = uri.to_s

uri = URI(ENV['REDIS_URI'] || ENV['COLONELAPI_REDIS_1_PORT'])
redis_backend = Rugged::Redis::Backend.new(host: uri.host, port: uri.port)
Colonel.config.rugged_backend = redis_backend

Document = Colonel::DocumentType.new('document') { index_name 'colonel-api' }

retries = [3, 5, 10]
begin
  Colonel::ElasticsearchProvider.initialize!
rescue => e
  if delay = retries.shift
    sleep delay
    retry
  else
    raise
  end
end

# The API
class App < Sinatra::Base
  set :bind, '0.0.0.0'

  before { content_type 'application/json' }

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

  get '/documents/:id' do |id|
    state = params['state'] || 'master'
    revision = Document.open(id).revisions[state]

    revision_hash(revision).to_json
  end

  put '/documents/:id' do |id|
    doc = Document.open(id)
    data = JSON.parse(request.body.read)
    doc.content = data['content']
    doc.save!({ name: data['name'], email: data['email'] }, data['message'])

    status 200
    body doc_hash(doc).to_json
  end

  post '/documents/:id/promote' do |id|
    doc = Document.open(id)
    data = JSON.parse(request.body.read)
    doc.promote! params['from'],
                 params['to'],
                 { name: data['name'], email: data['email'] },
                 data['message']

    status 200
    body doc_hash(doc).to_json
  end

  get '/documents/:id/revisions/:revision_id' do |id, revision_id|
    revision_hash(Document.open(id).revisions[revision_id]).to_json
  end

  get '/documents/:id/revisions' do |id|
    state = params['state'] || 'master'

    Document.open(id).history(state).map do |revision|
      {
        id: revision.id,
        name: revision.author[:name],
        email: revision.author[:email],
        message: revision.message
      }
    end.to_json
  end

  private

  def doc_hash(doc)
    {
      id: doc.id,
      content: doc.content
    }
  end

  def revision_hash(revision)
    {
      revision_id: revision.id,
      content: revision.content
    }
  end

  run! if app_file == $PROGRAM_NAME
end
