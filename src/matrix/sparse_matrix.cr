require "./matrix"
require "./submatrix"

module LA::Sparse
  abstract class Matrix(T) < LA::Matrix(T)
    getter nrows : Int32 = 0
    getter ncolumns : Int32 = 0
    property flags : MatrixFlags = MatrixFlags::None

    abstract def nonzeros : Int32

    def ==(other : Sparse::Matrix(T))
      return false unless nrows == other.nrows && ncolumns == other.ncolumns
      if other.nonzeros + self.nonzeros < nrows * ncolumns // 4
        # TODO - 2x speed if we account already checked elements
        a, b = self, other
        a, b = b, a if a.nonzeros < b.nonzeros
        a.each_with_index(all: false) do |v, i, j|
          return false if b.unsafe_fetch(i, j) != v
        end
        b.each_with_index(all: false) do |v, i, j|
          return false if a.unsafe_fetch(i, j) != v
        end
        true
      else
        super(other)
      end
    end
  end

  class COOMatrix(T) < Matrix(T)
    protected getter raw_columns : Array(Int32)
    protected getter raw_rows : Array(Int32)
    protected getter raw_values : Array(T)
    protected getter dictionary = {} of Tuple(Int32, Int32) => Int32

    def initialize(@nrows, @ncolumns, capacity = 0)
      @raw_rows = Array(Int32).new(capacity)
      @raw_columns = Array(Int32).new(capacity)
      @raw_values = Array(T).new(capacity)
      @flags = MatrixFlags.for_diag(@nrows == @ncolumns)
    end

    def initialize(@nrows, @ncolumns, rows : Array(Int32), columns : Array(Int32), values : Array(T), @flags = MatrixFlags::None, *, dont_clone : Bool = false, dont_check : Bool = false, dictionary = nil)
      if rows.size != columns.size
        raise ArgumentError.new("Can't construct COO Matrix from arrays of different size: rows.size=#{rows.size} != columns.size=#{columns.size}")
      end
      if rows.size != values.size
        raise ArgumentError.new("Can't construct COO Matrix from arrays of different size: rows.size=#{rows.size} != values.size=#{values.size}")
      end
      if dont_clone
        @raw_rows = rows
        @raw_columns = columns
        @raw_values = values
      else
        @raw_rows = rows.dup
        @raw_columns = columns.dup
        @raw_values = values.dup
      end
      if dictionary
        @dictionary = dictionary.dup
      else
        @dictionary = {} of Tuple(Int32, Int32) => Int32
        nonzeros.times do |i|
          row = @raw_rows[i]
          unless (0...@nrows).includes?(row)
            raise ArgumentError.new("Can't construct COO Matrix from arrays: rows[#{i}]=#{@raw_rows[i]} is outside (#{0}..#{@nrows})")
          end
          column = @raw_columns[i]
          unless (0...@ncolumns).includes?(column)
            raise ArgumentError.new("Can't construct COO Matrix from arrays: columns[#{i}]=#{@raw_columns[i]} is outside (#{0}..#{@ncolumns})")
          end
          @dictionary[{row, column}] = i
        end
      end
    end

    def nonzeros : Int32
      @raw_rows.size
    end

    def self.new(matrix : COOMatrix(T))
      new(matrix.nrows, matrix.ncolumns, matrix.raw_rows, matrix.raw_columns, matrix.raw_values, dictionary: matrix.dictionary, flags: matrix.flags)
    end

    def self.new(matrix : COOMatrix)
      new(matrix.nrows, matrix.ncolumns, matrix.raw_rows.dup, matrix.raw_columns.dup, matrix.raw_values.map { |v| T.new(v) }, dont_clone: true, dictionary: matrix.dictionary, flags: matrix.flags)
    end

    def self.new(matrix : LA::Matrix)
      if matrix.is_a? Sparse::Matrix
        result = new(matrix.nrows, matrix.ncolumns, matrix.nonzeros)
      else
        result = new(matrix.nrows, matrix.ncolumns)
      end
      matrix.each_with_index(all: false) do |v, i, j|
        result.push_element(i, j, v)
      end
      result.flags = matrix.flags
      result
    end

    def unsafe_fetch(i, j)
      if index = @dictionary[{i, j}]?
        @raw_values[index]
      else
        T.new(0.0)
      end
    end

    protected def push_element(i, j, v)
      @raw_rows << i
      @raw_columns << j
      @raw_values << T.new(v)
      @dictionary[{i, j}] = @raw_rows.size - 1
    end

    protected def add_element(i, j, v)
      if index = @dictionary[{i, j}]?
        @raw_values[index] += T.new(v)
      else
        # TODO - delete elements?
        push_element(i, j, v)
      end
    end

    def unsafe_set(i, j, value)
      clear_flags # TODO - not always?
      if index = @dictionary[{i, j}]?
        if value == T.new(0)
          remove_element(index)
        else
          @raw_values[index] = T.new(value)
        end
      else
        push_element(i, j, value)
      end
    end

    def dup
      COOMatrix(T).new(self)
    end

    def clone
      dup
    end

    def self.diag(nrows, ncolumns, values)
      raise ArgumentError.new("Too much elements for diag matrix") if values.size > {nrows, ncolumns}.min
      new(nrows, ncolumns, values.size)
      values.each_with_index do |v, i|
        push_element(i, i, v)
      end
    end

    def self.diag(nrows, ncolumns, &block)
      n = {nrows, ncolumns}.min
      new(nrows, ncolumns, n)
      n.times do |i|
        value = yield(i)
        push_element(i, i, T.new(v))
      end
    end

    def each_index(*, all = false, &block)
      if all
        super(all: true) { |i, j| yield(i, j) }
      else
        nonzeros.times do |i|
          yield(@raw_rows[i], @raw_columns[i])
        end
      end
    end

    def each_with_index(*, all = false, &block)
      if all
        super(all: true) { |v, i, j| yield(v, i, j) }
      else
        nonzeros.times do |i|
          yield(@raw_values[i], @raw_rows[i], @raw_columns[i])
        end
      end
    end

    def map_with_index!(&block)
      nonzeros.times do |i|
        @raw_values[i] = T.new(yield(@raw_values[i], @raw_rows[i], @raw_columns[i]))
      end
      self
    end

    def map_with_index(&block)
      values = @raw_values.map_with_index { |v, i| T.new(yield(v, @raw_rows[i], @raw_columns[i])) }
      COOMatrix(T).new(@nrows, @ncolumns, @raw_rows.dup, @raw_columns.dup, values, dont_clone: true, dictionary: @dictionary)
    end

    def map_with_index_f64(&block)
      values = @raw_values.map_with_index { |v, i| Float64.new(yield(v, @raw_rows[i], @raw_columns[i])) }
      COOMatrix(Float64).new(@nrows, @ncolumns, @raw_rows.dup, @raw_columns.dup, values, dont_clone: true, dictionary: @dictionary)
    end

    def map_with_index_complex(&block)
      values = @raw_values.map_with_index { |v, i| Complex.new(yield(v, @raw_rows[i], @raw_columns[i])) }
      COOMatrix(Complex).new(@nrows, @ncolumns, @raw_rows.dup, @raw_columns.dup, values, dont_clone: true, dictionary: @dictionary)
    end

    private def rebuild_dictionary
      @dictionary.clear
      nonzeros.times do |i|
        row = @raw_rows[i]
        column = @raw_columns[i]
        @dictionary[{row, column}] = i
      end
    end

    def transpose!
      return self if flags.symmetric?
      nonzeros.times do |i|
        @raw_rows[i], @raw_columns[i] = @raw_columns[i], @raw_rows[i]
      end
      @nrows, @ncolumns = @ncolumns, @nrows
      self.flags = flags.transpose
      rebuild_dictionary
      self
    end

    def transpose
      return clone if flags.symmetric?
      COOMatrix(T).new(@ncolumns, @nrows, @raw_columns, @raw_rows, @raw_values, flags: @flags.transpose)
    end

    def conjtranspose
      {% if T != Complex %}
        return transpose
      {% end %}
      return clone if flags.hermitian?
      COOMatrix(T).new(@ncolumns, @nrows, @raw_columns.dup, @raw_rows.dup, @raw_values.map(&.conj), flags: @flags.transpose, dont_clone: true)
    end

    # returns element-wise sum
    def +(m : LA::Matrix)
      result = clone.add!(T.new(1), m)
      result.flags = self.flags.sum(m.flags)
      result
    end

    def -(m : LA::Matrix)
      result = clone.add!(-T.new(1), m)
      result.flags = self.flags.sum(m.flags)
      result
    end

    def add!(k : Number | Complex, m : Sparse::Matrix)
      assert_same_size(m)
      m.each_with_index(all: false) do |v, i, j|
        add_element(i, j, k*v)
      end
      self.flags = self.flags.sum(m.flags.scale(k.is_a?(Complex) && k.imag != 0))
      self
    end

    def add!(k : Number | Complex, m : LA::Matrix)
      raise ArgumentError.new "can't `add!` dense matrix to sparse"
    end

    protected def remove_element(index)
      @dictionary.delete({@raw_rows[index], @raw_columns[index]})
      n = nonzeros - 1
      if n >= 0 && index != n
        @dictionary[{@raw_rows[n], @raw_columns[n]}] = index
        @raw_rows[index] = @raw_rows[n]
        @raw_columns[index] = @raw_columns[n]
        @raw_values[index] = @raw_values[n]
      end
      @raw_rows.pop
      @raw_columns.pop
      @raw_values.pop
    end

    def clear
      @dictionary.clear
      @raw_rows.clear
      @raw_columns.clear
      @raw_values.clear
      @flags = MatrixFlags.for_diag(square?)
    end

    def triu!(k = 0)
      (nonzeros - 1).downto(0) do |index|
        i = @raw_rows[index]
        j = @raw_columns[index]
        remove_element(index) if i > j - k
      end
      self.flags = self.flags.triu(k >= 0, square?)
      self
    end

    def tril!(k = 0)
      (nonzeros - 1).downto(0) do |index|
        i = @raw_rows[index]
        j = @raw_columns[index]
        remove_element(index) if i < j - k
      end
      self.flags = self.flags.tril(k <= 0, square?)
      self
    end

    def tril(k = 0)
      result = COOMatrix(T).new(@nrows, @ncolumns)
      each_with_index do |v, i, j|
        result.push_element(i, j, v) if i >= j - k
      end
      result.flags = self.flags.tril(k <= 0, square?)
      result
    end

    def triu(k = 0)
      result = COOMatrix(T).new(@nrows, @ncolumns)
      each_with_index do |v, i, j|
        result.push_element(i, j, v) if i <= j - k
      end
      result.flags = self.flags.triu(k >= 0, square?)
      result
    end

    def self.rand(nrows, ncolumns, *, nonzero_elements, rng : Random = Random::DEFAULT)
      raise ArgumentError.new("Too many nonzero elements, maximum is nrows*ncolumns/2") if nonzero_elements > nrows * ncolumns // 2
      result = new(nrows, ncolumns, capacity: nonzero_elements)
      nonzero_elements.times do
        i = j = 0
        loop do
          i = rng.rand(nrows)
          j = rng.rand(ncolumns)
          break if !result.dictionary.has_key?({i, j})
        end
        v = rng.rand
        result.push_element(i, j, v)
      end
      result.clear_flags
      result
    end

    def self.rand(nrows, ncolumns, *, fill_factor, rng : Random = Random::DEFAULT)
      result = new(nrows, ncolumns, capacity: (nrows*ncolumns*fill_factor*1.1).to_i)
      nrows.times do |i|
        ncolumns.times do |j|
          next if rng.rand >= fill_factor
          v = rng.rand
          result.push_element(i, j, v)
        end
      end
      result.clear_flags
      result
    end

    def to_general
      result = GeneralMatrix(T).new(nrows, ncolumns)
      self.each_with_index(all: false) do |v, i, j|
        result.unsafe_set(i, j, v)
      end
      result.flags = flags
      result
    end

    def to_dense
      to_general
    end
  end

#  class CSRMatrix(T) < Matrix(T)
#  end
end
