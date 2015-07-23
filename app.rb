require 'sinatra'
require 'colonel'
require 'rugged-redis'
require 'pry'

Colonel.config.elasticsearch_uri = 'elasticsearch:9200'

redis_backend = Rugged::Redis::Backend.new(host: 'redis', port: 6379)
Colonel.config.rugged_backend = redis_backend

Document = Colonel::DocumentType.new('document') { index_name 'colonel-api' }

Colonel::ElasticsearchProvider.initialize!

class App < Sinatra::Base
  set :bind, '0.0.0.0'

  get '/documents' do
    content_type :json
    Document.list(sort: {updated_at: 'desc'}).map do |doc|
      {
        id: doc.id,
        content: doc.content
      }
    end.to_json
  end

  get '/documents/:id/revisions' do |id|
    content_type :json
    Document.open(id).history.map do |revision|
      revision.content
    end.to_json
  end

  run! if app_file == $0
end
