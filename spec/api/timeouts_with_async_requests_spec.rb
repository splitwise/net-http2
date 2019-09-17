require 'spec_helper'

describe "Timeouts with async requests" do
  let(:port) { 9516 }
  let(:server) { NetHttp2::Dummy::Server.new(port: port) }
  let(:client) { NetHttp2::Client.new("http://localhost:#{port}", idle_timeout: 1) }

  before do
    server.listen
    server.on_req = Proc.new { |_req| sleep 3 }
  end

  after do
    client.close
    server.stop
  end

  context "when :error callback is defined" do

    before do
      @exception = nil
      client.on(:error) do |exc|
        @exception = exc
      end
    end

    it "calls the :error callback" do
      request = client.prepare_request(:get, '/path')

      client.call_async(request)
      client.join

      expect(@exception).to be_a NetHttp2::TimeoutError
      expect(@exception.message).to eq 'Connection was idle'
    end

    it "repairs the connection for subsequent calls" do
      close_next_socket = true
      server.on_req = Proc.new do |_req, _stream, socket|
        if close_next_socket
          close_next_socket = false
          socket.close
        else
          NetHttp2::Response.new(
            headers: {":status" => "200"},
            body: "response body"
          )
        end
      end

      request = client.prepare_request(:get, '/path')
      client.call_async(request)
      client.join

      headers = nil
      body = ''
      completed = false
      request = client.prepare_request(:get, '/path')
      request.on(:headers) { |hs| headers = hs }
      request.on(:body_chunk) { |chunk| body << chunk }
      request.on(:close) { completed = true }

      client.call_async(request)
      client.join

      expect(headers).to_not be_nil
      expect(headers[':status']).to eq "200"
      expect(headers['content-length']).to eq "13"

      expect(body).to eq "response body"

      expect(completed).to eq true
    end
  end

  context "when :error callback is not defined" do

    it "raises a TimeoutError in main thread" do
      request = client.prepare_request(:get, '/path')

      client.call_async(request)

      expect { client.join }.to raise_error NetHttp2::TimeoutError, 'Connection was idle'
    end

    it "repairs the connection for subsequent calls" do
      close_next_socket = true
      server.on_req = Proc.new do |_req, _stream, socket|
        if close_next_socket
          close_next_socket = false
          socket.close
        else
          NetHttp2::Response.new(
            headers: {":status" => "200"},
            body: "response body"
          )
        end
      end

      request = client.prepare_request(:get, '/path')

      client.call_async(request)
      wait_for { client.join } rescue NetHttp2::TimeoutError

      headers = nil
      body = ''
      completed = false
      request = client.prepare_request(:get, '/path')
      request.on(:headers) { |hs| headers = hs }
      request.on(:body_chunk) { |chunk| body << chunk }
      request.on(:close) { completed = true }

      client.call_async(request)
      client.join

      expect(headers).to_not be_nil
      expect(headers[':status']).to eq "200"
      expect(headers['content-length']).to eq "13"

      expect(body).to eq "response body"

      expect(completed).to eq true
    end
  end
end
