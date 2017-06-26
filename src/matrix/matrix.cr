require "complex"

module Linalg
  # TODO - Complex64?
  SUPPORTED_TYPES = {Float32, Float64, Complex}

  @[Flags]
  enum MatrixFlags
    Symmetric
    Hermitian
    PositiveDefinite
    # Hessenberg
    # Band
    # Diagonal
    # Bidiagonal
    # Tridiagonal
    Triangular
    Orthogonal
    Unitary    = Orthogonal
    Lower
  end

  # class that provide all utility matrix functions
  # TODO - sums on cols\nrows, check numpy for more (require previous point?)
  # TODO - saving/loading to files (what formats? csv?)
  # TODO - replace [] to unsafe at most places
  module Matrix(T)
    # used in constructors to limit T at compile-time
    protected def check_type
      {% unless T == Float32 || T == Float64 || T == Complex %}
        {% raise "Wrong matrix members type: #{T}. Types supported by Linalg are: #{SUPPORTED_TYPES}" %}
      {% end %}
    end

    # to_unsafe method raises at runtime and is overriden by matrix that actually have pointer
    def to_unsafe
      raise ArgumentError.new("Virtual matrix can't be passed unsafe!")
    end

    def size
      {nrows, ncolumns}
    end

    # creates generic matrix with same content. Useful for virtual matrices
    def clone
      GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        unsafe_at(i, j)
      end.tap { |it| it.flags = flags }
    end

    # matrix product to given m
    def *(m : Matrix(T))
      if ncolumns != m.nrows
        raise ArgumentError.new("matrix size should match ([#{nrows}x#{ncolumns}] * [#{m.nrows}x#{m.ncolumns}]")
      end
      result = GeneralMatrix(T).new(nrows, m.ncolumns) do |i, j|
        (0...ncolumns).sum { |k| self[i, k]*m[k, j] }
      end
    end

    # multiplies at scalar
    def *(k : Number | Complex)
      result = GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        self[i, j]*k
      end
    end

    # divides at scalar
    def /(k : Number | Complex)
      result = GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        self[i, j] / k
      end
    end

    # returns element-wise sum
    def +(m : Matrix(T))
      if ncolumns != m.ncolumns || nrows != m.nrows
        raise ArgumentError.new("matrix size should match ([#{nrows}x#{ncolumns}] + [#{m.nrows}x#{m.ncolumns}]")
      end
      result = GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        self[i, j] + m[i, j]
      end
    end

    # returns element-wise subtract
    def -(m : Matrix(T))
      if ncolumns != m.ncolumns || nrows != m.nrows
        raise ArgumentError.new("matrix size should match ([#{nrows}x#{ncolumns}] - [#{m.nrows}x#{m.ncolumns}]")
      end
      result = GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        self[i, j] - m[i, j]
      end
    end

    # returns transposed matrix
    def transpose
      return clone if flags.symmetric?
      GeneralMatrix(T).new(ncolumns, nrows) do |i, j|
        self[j, i]
      end.tap do |m|
        m.flags = flags
        if flags.triangular?
          m.flags ^= MatrixFlags::Lower
        end
      end
    end

    # returns transposed matrix
    def conjtranspose
      {% raise "Matrix must be Complex for conjtranspose" unless T == Complex %}
      return clone if flags.hermitian?
      GeneralMatrix(T).new(ncolumns, nrows) do |i, j|
        self[j, i].conj
      end.tap do |m|
        m.flags = flags
        if flags.triangular?
          m.flags ^= MatrixFlags::Lower
        end
      end
    end

    # returns kroneker product with matrix b
    def kron(b : Matrix(T))
      Matrix(T).kron(self, b)
    end

    # same as tril in scipy - returns lower triangular or trapezoidal part of matrix
    def tril(k = 0)
      x = GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        i >= j - k ? self[i, j] : 0
      end
      if k >= 0
        x.assume! MatrixFlags::Triangular | MatrixFlags::Lower
      end
      x
    end

    # same as triu in scipy - returns upper triangular or trapezoidal part of matrix
    def triu(k = 0)
      x = GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        i <= j - k ? self[i, j] : 0
      end
      if k >= 0
        x.assume! MatrixFlags::Triangular
      end
      x
    end

    # like a tril in scipy - remove all elements above k-diagonal
    def tril!(k = 0)
      (nrows*ncolumns).times do |index|
        i = index / ncolumns
        j = index % ncolumns
        @raw[index] = T.new(0) if i < j - k
      end
      if k <= 0
        self.assume! MatrixFlags::Triangular | MatrixFlags::Lower
      end
      self
    end

    # like a triu in scipy - remove all elements below k-diagonal
    def triu!(k = 0)
      (nrows*ncolumns).times do |index|
        i = index / ncolumns
        j = index % ncolumns
        @raw[index] = T.new(0) if i > j - k
      end
      if k >= 0
        self.assume! MatrixFlags::Triangular
      end
      self
    end

    # converts to string, with linefeeds before and after matrix:
    # [1, 2, 3, .... 10]
    # [11, 12, 13, .... 20]
    # ...
    # [91, 92, 93, .... 100]
    def to_s(io)
      io << "\n"
      nrows.times do |i|
        io << "["
        ncolumns.times do |j|
          io << ", " unless j == 0
          io << self[i, j]
        end
        io << "]\n"
      end
      io << "\n"
    end

    def each(&block)
      nrows.times do |row|
        ncolumns.times do |column|
          yield self.unsafe_at(row, column)
        end
      end
    end

    def each_index(&block)
      nrows.times do |row|
        ncolumns.times do |column|
          yield row, column
        end
      end
    end

    def each_with_index(&block)
      nrows.times do |row|
        ncolumns.times do |column|
          yield self.unsafe_at(row, column), row, column
        end
      end
    end

    def ==(other)
      return false unless nrows == other.nrows && ncolumns == other.ncolumns
      each_with_index do |value, row, column|
        return false if other.unsafe_at(row, column) != value
      end
      true
    end

    # changes nrows and ncolumns of matrix (total number of elements must not change)
    def reshape(anrows, ancolumns)
      clone.reshape!(anrows, ancolumns)
    end

    # returns True if matrix is square and False otherwise
    def square?
      nrows == ncolumns
    end

    # return matrix repeated `arows` times by vertical and `acolumns` times by horizontal
    def repmat(arows, acolumns)
      GeneralMatrix(T).new(nrows*arows, ncolumns*acolumns) do |i, j|
        self[i % nrows, j % ncolumns]
      end
    end

    def [](i, j)
      if j >= 0 && j < ncolumns && i >= 0 && i < nrows
        unsafe_at(i, j)
      else
        raise IndexError.new("access to [#{i}, #{j}] in matrix with size #{nrows}x#{ncolumns}")
      end
    end

    def []=(i, j, value)
      if j >= 0 && j < ncolumns && i >= 0 && i < nrows
        unsafe_set(i, j, value)
      else
        raise IndexError.new("access to [#{i}, #{j}] in matrix with size #{nrows}x#{ncolumns}")
      end
    end

    # return submatrix over given ranges.
    def [](arows : Range(Int32, Int32), acolumns : Range(Int32, Int32))
      anrows = arows.end + (arows.excludes_end? ? 0 : 1) - arows.begin
      ancols = acolumns.end + (acolumns.excludes_end? ? 0 : 1) - acolumns.begin
      SubMatrix(T).new(self, {arows.begin, acolumns.begin}, {anrows, ancols})
    end

    def [](row : Int32, acolumns : Range(Int32, Int32))
      self[row..row, acolumns]
    end

    def [](arows : Range(Int32, Int32), column : Int32)
      self[arows, column..column]
    end

    def row(i)
      SubMatrix(T).new(self, {i, 0}, {1, ncolumns})
    end

    def column(i)
      SubMatrix(T).new(self, {0, i}, {nrows, 1})
    end

    def []=(arows : Range(Int32, Int32), acolumns : Range(Int32, Int32), value)
      submatrix = self[arows, acolumns]
      if value.is_a? Matrix
        raise IndexError.new("submatrix size must match assigned value") unless submatrix.size == value.size
        submatrix.each_index { |i, j| submatrix.unsafe_set i, j, value.unsafe_at(i, j) }
      else
        submatrix.each_index { |i, j| submatrix.unsafe_set i, j, value }
      end
    end

    def []=(row : Int32, acolumns : Range(Int32, Int32), value)
      self[row..row, acolumns] = value
    end

    def []=(nrows : Range(Int32, Int32), column : Int32, value)
      self[nrows, column..column] = value
    end

    def assume!(flag : MatrixFlags)
      @flags |= flag
    end

    # TODO - better eps
    private def tolerance
      {% if T == Float32 %}
        2e-7
      {% else %}
        2e-16
      {% end %} * norm(MatrixNorm::Max)
    end

    # TODO - check for all flags
    private def detect_single(flag : MatrixFlags)
      case flag
      when .symmetric?
      when .hermitian?
      when .positive_definite?
      when .triangular?
      when .orthogonal?
        square? && (self*self.t - Matrix(T).eye(nrows)).norm(MatrixNorm::Max) < tolerance
      when .lower?
        false
      else
        false
      end
    end

    def clear_flags
      @flags = MatrixFlags.new(0)
    end

    def self.rand(nrows, ncolumns, rng = Random::DEFAULT)
      GeneralMatrix(T).new(nrows, ncolumns) { |i, j| rng.rand }
    end

    def self.zeros(nrows, ncolumns)
      GeneralMatrix(T).new(nrows, ncolumns)
    end

    def self.ones(nrows, ncolumns)
      GeneralMatrix(T).new(nrows, ncolumns) { |i, j| 1 }
    end

    def self.repmat(a : Matrix(T), nrows, ncolumns)
      a.repmat(nrows, ncolumns)
    end

    def self.diag(nrows, ncolumns, value : Number | Complex)
      diag(nrows, ncolumns) { value }
    end

    def self.diag(nrows, ncolumns, values)
      GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        i == j ? values[i] : 0
      end
    end

    def self.diag(values)
      diag(values.size, values.size, values)
    end

    def self.diag(nrows, ncolumns, &block)
      GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        i == j ? yield(i) : 0
      end
    end

    def self.kron(a, b)
      GeneralMatrix(T).new(a.nrows*b.nrows, a.ncolumns*b.ncolumns) do |i, j|
        a[i / b.nrows, j / b.ncolumns] * b[i % b.nrows, j % b.ncolumns]
      end
    end

    def self.tri(nrows, ncolumns, k = 0)
      GeneralMatrix(T).new(nrows, ncolumns) do |i, j|
        i >= j - k ? 1 : 0
      end
    end

    def self.identity(n)
      GeneralMatrix(T).new(n, n) { |i, j| i == j ? 1 : 0 }
    end

    def self.eye(n)
      self.identity(n)
    end

    def t
      transpose
    end

    def t!
      transpose!
    end

    def conjt
      conjtranspose
    end

    def conjt!
      conjtranspose!
    end
  end

  alias Mat = Matrix(Float64)
  alias Mat32 = Matrix(Float32)
  alias MatComplex = Matrix(Complex)
end
