require "./matrix"

module LA
  alias RowColumn = {Int32, Int32}

  # it's like Slice, but for matrices.
  # in future will be improved to provide same interface as matrix
  class SubMatrix(T)
    include Matrix(T)
    getter offset
    getter size
    property flags = MatrixFlags.new(0)

    def initialize(@base : Matrix(T), @offset : RowColumn, @size : RowColumn)
      raise IndexError.new("submatrix offset can't be negative") if @offset.any? &.<(0)
      if @offset[0] + @size[0] > @base.nrows || @offset[1] + @size[1] > @base.ncolumns
        raise IndexError.new("submatrix size exceeds matrix size")
      end
    end

    def nrows
      @size[0]
    end

    def ncolumns
      @size[1]
    end

    def unsafe_set(x, y, value)
      @base.unsafe_set(@offset[0] + x, @offset[1] + y, value)
    end

    def unsafe_at(x, y)
      @base.unsafe_at(@offset[0] + x, @offset[1] + y)
    end
  end
end
