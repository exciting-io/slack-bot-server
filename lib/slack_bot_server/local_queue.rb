class SlackBotServer::LocalQueue
  def initialize
    @queue = Queue.new
  end

  def push(value)
    @queue << value
  end

  def pop
    value = @queue.pop(true) rescue ThreadError
    value == ThreadError ? nil : value
  end
end
