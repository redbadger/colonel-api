require 'sinatra/base'
require "sinatra/reloader" if :development?
require 'colonel'
require 'rugged-redis'
require 'pry'
require 'json'

uri = URI(ENV['ELASTICSEARCH_1_PORT'])
uri.scheme = 'http' # is tcp otherwise
Colonel.config.elasticsearch_uri = uri.to_s

uri = URI(ENV['REDIS_1_PORT'])
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

  configure :development do
    register Sinatra::Reloader
  end

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

  get '/search' do
    hits = Document.search(query(params), history: true)
    return nil unless hits.any?
    doc = hits.first
    body doc_hash(doc).to_json
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

  def query(params)
    {
      query: {
        constant_score: {
          filter: {
            and: term_array(params[:q]) << {term: {state: params[:state] || 'master'}}
          }
        }
      }
    }
  end

  def search(query, opts = {size: 1000, scope: 'latest'})
    hits = Document.search(query, opts)
    hits.map { |hit| Page.new(nil, document: hit) }
  end

  def term_array(hash)
    hash = hash.to_hash if hash.is_a?(Hash)
    hash.each_with_object([]) do |(k,v), h|
      value = {}
      value[k.to_sym] = v
      h << {term: value}
    end
  end

  run! if app_file == $PROGRAM_NAME
end
