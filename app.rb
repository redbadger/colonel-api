require 'sinatra/base'
require 'sinatra/reloader' if :development?
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

  helpers do
    def post_params
      @parsed_body ||= JSON.parse(request.body.read)
    rescue
      {}
    end
  end

  get '/documents' do
    Document.list(sort: { updated_at: 'desc' }).map do |doc|
      doc_hash(doc)
    end.to_json
  end

  post '/documents' do
    doc = Document.new(post_params['content'])
    doc.save!(
      { name: post_params['name'], email: post_params['email'] },
      post_params['message']
    )

    status 201
    doc_hash(doc).to_json
  end

  get '/documents/:id' do |id|
    state = params['state'] || 'master'
    revision = Document.open(id).revisions[state]

    halt 404 unless revision
    revision_hash(revision).to_json
  end

  put '/documents/:id' do |id|
    doc = Document.open(id)
    doc.content = post_params['content']
    doc.save!(
      { name: post_params['name'], email: post_params['email'] },
      post_params['message']
    )

    doc_hash(doc).to_json
  end

  post '/documents/:id/promote' do |id|
    doc = Document.open(id)
    doc.promote! params['from'],
                 params['to'],
                 { name: post_params['name'], email: post_params['email'] },
                 post_params['message']

    doc_hash(doc).to_json
  end

  get '/documents/:id/revisions/:revision_id' do |id, revision_id|
    revision_hash(Document.open(id).revisions[revision_id]).to_json
  end

  get '/documents/:id/revisions' do |id|
    state = params['state'] || 'master'

    Document.open(id).history(state)
      .map { |revision| history_hash(revision) }.to_json
  end

  get '/documents/:id/history' do |id|
    states = params[:states] || [:master]
    states.flat_map { |state| Document.open(id).history(state.to_sym).to_a }
      .sort_by { |r| [r.author[:time], r.type] }
      .reverse
      .map { |revision| history_hash(revision) }.to_json
  end

  post '/search' do
    halt 400 if post_params.empty?

    hits = Document.search(post_params)
    hits.map { |hit| doc_hash(hit) }.to_json
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

  def history_hash(revision)
    hash = {
      revision_id: revision.id,
      name: revision.author[:name],
      email: revision.author[:email],
      message: revision.message
    }
    hash['state'] = revision.state if defined? revision.state
    hash
  end

  run! if app_file == $PROGRAM_NAME
end
