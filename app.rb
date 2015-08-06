require 'sinatra/base'
require 'sinatra/reloader' if :development?
require 'colonel'
require 'rugged-redis'
require 'pry'
require 'json'

uri = URI(ENV['COLONELAPI_ELASTICSEARCH_1_PORT'])
uri.scheme = 'http' # is tcp otherwise
Colonel.config.elasticsearch_uri = uri.to_s

uri = URI(ENV['COLONELAPI_REDIS_1_PORT'])
redis_backend = Rugged::Redis::Backend.new(host: uri.host, port: uri.port)
Colonel.config.rugged_backend = redis_backend

Document = Colonel::DocumentType.new('document') { index_name 'colonel-api' }

retries = [3, 5, 10]
begin
  Colonel::ElasticsearchProvider.initialize!
rescue
  delay = retries.shift
  if delay
    sleep delay
    retry
  else
    raise
  end
end

# The API
class App < Sinatra::Base
  set :bind, '0.0.0.0'

  configure :development do
    register Sinatra::Reloader
  end

  before { content_type 'application/json' }

  get '/documents' do
    size = params[:size] || 10
    from = params[:from] || 0

    Document.list(
      size: size,
      from: from,
      sort: { updated_at: 'desc' }
    ).map do |doc|
      { id: doc.id }
    end.to_json
  end

  post '/documents' do
    data = JSON.parse(request.body.read)
    doc = Document.new(data['content'])
    doc.save!({ name: data['name'], email: data['email'] }, data['message'])

    status 201
    { id: doc.id }.to_json
  end

  put '/documents/:id' do |id|
    doc = Document.open(id)
    data = JSON.parse(request.body.read)
    doc.content = data['content']
    doc.save!({ name: data['name'], email: data['email'] }, data['message'])

    { id: doc.id }.to_json
  end

  post '/documents/:id/promote' do |id|
    doc = Document.open(id)
    data = JSON.parse(request.body.read)
    doc.promote! params['from'],
                 params['to'],
                 { name: data['name'], email: data['email'] },
                 data['message']

    { id: doc.id } .to_json
  end

  get '/documents/:id/revisions/:revision_id_or_state' do |id, id_or_state|
    revision_hash(Document.open(id).revisions[id_or_state]).to_json
  end

  get '/documents/:id/revisions' do |id|
    state = params['state'] || 'master'

    Document.open(id).history(state).map do |revision|
      revision_hash(revision)
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
      commit: {
        id: revision.id,
        name: revision.author[:name],
        email: revision.author[:email],
        message: revision.message,
        timestamp: revision.timestamp.iso8601
      },
      content: revision.content
    }
  end

  run! if app_file == $PROGRAM_NAME
end
