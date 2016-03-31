# A local implementation of a queue.
#
# Obviously this can't be used to communicate between
# multiple processes, let alone multiple machines, but
# it serves to demonstrate the expected API.
class SlackBotServer::LocalQueue
  # Creates a new local in-memory queue
  def initialize
    @queue = Queue.new
  end

  # Push a value onto the back of the queue
  def push(value)
    @queue << value
  end

  # Pop a value from the front of the queue
  # @return [Object, nil] returns the object from the front of the
  #    queue, or nil if the queue is empty
  def pop
    value = @queue.pop(true) rescue ThreadError
    value == ThreadError ? nil : value
  end

  # Clear the queue
  # @return [nil]
  def clear
    @queue = Queue.new
  end
end
