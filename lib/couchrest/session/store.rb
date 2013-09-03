class CouchRest::Session::Store < ActionDispatch::Session::AbstractStore

  include CouchRest::Model::Configuration
  include CouchRest::Model::Connection

  class << self
    def marshal(data)
      ::Base64.encode64(Marshal.dump(data)) if data
    end

    def unmarshal(data)
      Marshal.load(::Base64.decode64(data)) if data
    end

  end

  def initialize(app, options = {})
    super
    self.class.set_options(options)
  end

  def self.set_options(options)
    @options = options
  end

  # just fetch from the config
  def self.database
    @database ||= initialize_database
  end

  def self.initialize_database
    use_database @options[:database] || "sessions"
  end

  def database
    self.class.database
  end

  private

  def get_session(env, sid)
    if sid
      doc = secure_get(sid)
      [sid, doc.to_session]
    else
      [generate_sid, {}]
    end
  rescue RestClient::ResourceNotFound
    # session data does not exist anymore
    return [sid, {}]
  end

  def set_session(env, sid, session, options)
    doc = build_or_update_doc(sid, session, options[:marshal_data])
    doc.save
    return sid
  end

  def destroy_session(env, sid, options)
    doc = secure_get(sid)
    doc.delete
    generate_sid unless options[:drop]
  rescue RestClient::ResourceNotFound
    # already destroyed - we're done.
    generate_sid unless options[:drop]
  end

  def build_or_update_doc(sid, session, marshal_data)
    marshal_data = true if marshal_data.nil?
    doc = secure_get(sid)
    doc.update data_for_doc(session, marshal_data)
    return doc
  rescue RestClient::ResourceNotFound
    data = data_for_doc(session, marshal_data).merge({"_id" => sid})
    return CouchRest::Session::Document.new(CouchRest::Document.new(data))
  end

  def data_for_doc(session, marshal_data)
    if marshal_data
      { "data" => self.class.marshal(session) }
    else
      session.merge({"not_marshalled" => true})
    end
  end

  # prevent access to design docs
  # this should be prevented on a couch permission level as well.
  # but better be save than sorry.
  def secure_get(sid)
    raise RestClient::ResourceNotFound if /^_design\/(.*)/ =~ sid
    CouchRest::Session::Document.new(database.get(sid))
  end
end

