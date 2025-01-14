require "../matrix/*"
require "./lapack_helper"

module LA
  enum LSMethod
    Auto       = 0
    QR
    Orthogonal
    SVD
    LS         = QR
    LSY        = Orthogonal
    LSD        = SVD
  end

  enum RankMethod
    SVD
    QRP
  end

  enum MatrixNorm
    Frobenius
    One
    # Two
    Inf
    MaxAbs
  end

  class LinAlgError < Exception
  end

  def self.inv(matrix, *, overwrite_a = false)
    overwrite_a ? matrix.inv! : matrix.inv
  end

  def self.solve(a, b, *, overwrite_a = false, overwrite_b = false)
    a.solve(b, overwrite_a: overwrite_a, overwrite_b: overwrite_b)
  end

  def self.lstsq(a, b, method : LSMethod = LSMethod::Auto, *, overwrite_a = false, overwrite_b = false, cond = -1)
    a.lstsq(b, method, overwrite_a: overwrite_a, overwrite_b: overwrite_b, cond: cond)
  end

  def self.solvels(a, b, *, overwrite_a = false, overwrite_b = false, cond = -1)
    a.solvels(b, overwrite_a: overwrite_a, overwrite_b: overwrite_b, cond: cond)
  end

  def self.svd(matrix, *, overwrite_a = false)
    matrix.svd(overwrite_a: overwrite_a)
  end

  abstract class Matrix(T)
    private def uplo
      flags.lower_triangular? ? 'L'.ord.to_u8 : 'U'.ord.to_u8
    end

    private def adjust_symmetric
      f = flags
      each_with_index { |v, i, j| unsafe_set(j, i, v) if i < j }
      self.flags = f
    end

    private def adjust_triangular
      triu! if flags.upper_triangular?
      tril! if flags.lower_triangular?
    end

    def inv!
      raise ArgumentError.new("can't invert nonsquare matrix") unless square?
      return transpose! if flags.orthogonal?
      n = self.nrows
      if flags.triangular?
        lapack(trtri, uplo, 'N'.ord.to_u8, n, self, n)
        adjust_triangular
      elsif flags.positive_definite?
        lapack(potrf, uplo, n, self, n)
        lapack(potri, uplo, n, self, n)
        adjust_symmetric
      elsif {{T == Complex}} && flags.hermitian?
        {% if T == Complex %}
          ipiv = Slice(Int32).new(n)
          lapack(hetrf, uplo, n, self, n, ipiv)
          lapack(hetri, uplo, n, self, n, ipiv, worksize: [n])
          adjust_symmetric
        {% else %}
          raise "error"
        {% end %}
      elsif flags.symmetric?
        ipiv = Slice(Int32).new(n)
        lapack(sytrf, uplo, n, self, n, ipiv)
        lapack(sytri, uplo, n, self, n, ipiv, worksize: [2*n])
        adjust_symmetric
      else
        ipiv = Slice(Int32).new(n)
        lapack(getrf, n, n, self, n, ipiv)
        lapack(getri, n, self, n, ipiv)
      end
      self
    end

    def inv
      clone.inv!
    end

    def pinv 
      clone.pinv! 
    end

    def pinv! 
      # Pure Crystal implementation since LAPACK has no direct implementation of pseudo inverse
      u, s, vt = self.svd
      v = vt.transpose
      u_transpose = u.transpose

      s_inverse = s.map { |e|
        if e != 0
          1.0 / e
        else
          e
        end
      }
      s_dash : GeneralMatrix(T) = GeneralMatrix(T).diag(s_inverse).transpose

      append_rows = 0
      append_cols = 0

      if v.ncolumns >= s_dash.nrows
        append_rows = v.ncolumns - s_dash.nrows
      else
        puts "S` #{s_dash}"
        puts "v #{v}"
        raise Exception.new("Invalid dimension, S` larger than v")
      end

      if u_transpose.nrows >= s_dash.ncolumns
        append_cols = u_transpose.nrows - s_dash.ncolumns
      else
        puts "S` #{s_dash}\nShape #{s_dash.shape}"
        puts "U #{u_transpose}\nShape #{u_transpose.shape}"
        raise Exception.new("Invalid dimension, S` larger than U")
      end

      append_rows.times {
        s_dash = s_dash.append_row_zeros
      }

      append_cols.times {
        s_dash = s_dash.append_column_zeros
      }
      return v * s_dash * u_transpose
    end

    def append_column_zeros : GeneralMatrix(T)
      i = 0
      matrix_array = self.to_a
      tmp = Array(T).new

      while i < matrix_array.size
        if (i > 0 && i % self.ncolumns == 0)
          tmp << T.new(0)
          tmp << matrix_array[i]
        else
          tmp << matrix_array[i]
        end
        i += 1
      end

      tmp << T.new(0)

      appended_matrix = GeneralMatrix(T).new(self.nrows, self.ncolumns + 1, tmp)

      return appended_matrix
    end
      
    def append_row_zeros : GeneralMatrix(T)
      zeros = [T.new(0)] * self.ncolumns
      matrix_array = self.to_a
      matrix_array += zeros
      appended_matrix = GeneralMatrix(T).new(self.nrows + 1, self.ncolumns, matrix_array)
      return appended_matrix
    end

    def shape : Array(Int32)
      return [self.nrows, self.ncolumns]
    end

    def solve(b : self, *, overwrite_a = false, overwrite_b = false)
      raise ArgumentError.new("nrows of a and b must match") unless nrows == b.nrows
      raise ArgumentError.new("a must be square") unless square?
      a = overwrite_b ? self : self.clone
      x = overwrite_b ? b : b.clone
      n = nrows
      if flags.triangular?
        lapack(trtrs, uplo, 'N'.ord.to_u8, 'N'.ord.to_u8, n, b.nrows, a, n, x, b.nrows)
      elsif flags.positive_definite?
        lapack(posv, 'U'.ord.to_u8, n, b.ncolumns, a, n, x, b.nrows)
      elsif flags.hermitian?
        {% if T == Complex %}
          ipiv = Slice(Int32).new(n)
          lapack(hesv, uplo, n, b.ncolumns, a, n, ipiv, x, b.nrows)
        {% end %}
      elsif flags.symmetric?
        ipiv = Slice(Int32).new(n)
        lapack(sysv, uplo, n, b.ncolumns, a, n, ipiv, x, b.nrows)
      else
        ipiv = Slice(Int32).new(n)
        lapack(gesv, n, b.ncolumns, a, n, ipiv, x, b.nrows)
      end
      a.clear_flags
      x.clear_flags
      x
    end

    def det(*, overwrite_a = false)
      raise ArgumentError.new("matrix must be square") unless square?
      if flags.triangular?
        return diag.product
      end
      lru = overwrite_a ? self : self.clone
      ipiv = Slice(Int32).new(nrows)
      lapack(getrf, nrows, nrows, lru, nrows, ipiv)
      lru.clear_flags
      lru.diag.product
    end

    def solvels(b : self, *, overwrite_a = false, overwrite_b = false, cond = -1)
      raise ArgumentError.new("nrows of a and b must match") unless nrows == b.nrows
      a = overwrite_a ? self : self.clone
      if ncolumns > nrows
        # make room for residuals
        x = GeneralMatrix(T).new(ncolumns, b.ncolumns) { |r, c| r < nrows ? b.unsafe_fetch(r, c) : T.new(0) }
      else
        x = overwrite_b ? b : b.clone
      end
      lapack(gels, 'N'.ord.to_u8, nrows, ncolumns, b.ncolumns, a, nrows, x, x.nrows)
      a.clear_flags
      x.clear_flags
      x
    end

    def lstsq(b : self, method : LSMethod = LSMethod::Auto, *, overwrite_a = false, overwrite_b = false, cond = -1)
      raise ArgumentError.new("nrows of a and b must match") unless nrows == b.nrows
      if method.auto?
        method = LSMethod::QR
      end
      a = overwrite_a ? self : self.clone
      if ncolumns > nrows
        # make room for residuals
        x = GeneralMatrix(T).new(ncolumns, b.ncolumns) { |r, c| r < nrows ? b.unsafe_fetch(r, c) : T.new(0) }
      else
        x = overwrite_b ? b : b.clone
      end
      rank = 0
      case method
      when .ls?
        lapack(gels, 'N'.ord.to_u8, nrows, ncolumns, b.ncolumns, a, nrows, x, x.nrows)
        s = of_real_type(Array, 0)
      when .lsd?
        ssize = {nrows, ncolumns}.min
        s = of_real_type(Array, ssize)
        rcond = of_real_type(cond)
        lapack(gelsd, nrows, ncolumns, b.ncolumns, a, nrows, x, x.nrows, s, rcond, rank)
      when .lsy?
        jpvt = Slice(Int32).new(ncolumns)
        rcond = of_real_type(cond)
        lapack(gelsy, nrows, ncolumns, b.ncolumns, a, nrows, x, x.nrows, jpvt, rcond, rank, worksize: [2*ncolumns])
        s = of_real_type(Array, 0)
      else
        s = of_real_type(Array, 0)
      end
      a.clear_flags
      x.clear_flags
      {x, rank, s}
    end

    def svd(*, overwrite_a = false)
      a = overwrite_a ? self : self.clone
      m = nrows
      n = ncolumns
      mn = {m, n}.min
      mx = {m, n}.max
      s = of_real_type(Array, mn)
      u = GeneralMatrix(T).new(m, m)
      vt = GeneralMatrix(T).new(n, n)
      lapack(gesdd, 'A'.ord.to_u8, m, n, a, nrows, s, u, m, vt, n, worksize: [{5*mn*mn + 5*mn, 2*mx*mn + 2*mn*mn + mn}.max, 8*mn])
      a.clear_flags
      return {u, s, vt}
    end

    def svdvals(*, overwrite_a = false)
      a = overwrite_a ? self : self.clone
      m = nrows
      n = ncolumns
      mn = {m, n}.min
      mx = {m, n}.max
      s = of_real_type(Array, mn)
      lapack(gesdd, 'N'.ord.to_u8, m, n, a, nrows, s, nil, m, nil, n, worksize: [5*mn, 8*mn])
      a.clear_flags
      s
    end

    def balance!(*, permute = true, scale = true, separate = false)
      raise ArgumentError.new("matrix must be square") unless square?
      n = self.nrows
      job = if permute && scale
              'B'
            elsif permute
              'P'
            elsif scale
              'S'
            else
              # don't call anything, return identity matrix
              return separate ? Matrix(T).ones(1, n) : Matrix(T).identity(n)
            end
      s = GeneralMatrix(T).new(1, n)
      ilo = 0
      ihi = 0
      lapack(gebal, job.ord.to_u8, n, self, n, ilo, ihi, s)
      separate ? s : Matrix(T).diag(s.raw)
    end

    def balance(*, permute = true, scale = true, separate = false)
      a = clone
      s = a.balance!(permute: permute, scale: scale, separate: separate)
      {a, s}
    end

    def hessenberg!(*, calc_q = false)
      raise ArgumentError.new("matrix must be square") unless square?
      # idea from scipy.
      # no need to calculate if size <= 2
      if nrows < 2
        q = calc_q ? Matrix(T).identity(nrows) : Matrix(T).zeros(1, 1)
        return {self, q}
      end
      {% if flag?(:darwin) %}
        raise "Hessenberg decomposition is not supported on mac"
      {% end %}

      n = nrows
      s = of_real_type(Slice, n)
      lapack(gebal, 'S'.ord.to_u8, n, self, n, ilo, ihi, s)
      clear_flags
      tau = GeneralMatrix(T).new(1, n)
      lapack(gehrd, n, ilo, ihi, self, ncolumns, tau)
      if calc_q
        q = clone
        lapack(orghr, n, ilo, ihi, q, ncolumns, tau)
        q.flags = MatrixFlags::Orthogonal
      else
        q = Matrix(T).zeros(1, 1)
      end
      triu!(-1)
      {self, q}
    end

    def hessenberg!
      q = hessenberg!(calc_q: false)
      self
    end

    def hessenberg(*, calc_q = false)
      x = self.clone
      x.hessenberg!(calc_q: calc_q)
    end

    def hessenberg
      clone.hessenberg!
    end

    # returns matrix norm
    def norm(kind : MatrixNorm = MatrixNorm::Frobenius)
      let = case kind
            when .frobenius?
              'F'
            when .one?
              'O'
            when .inf?
              'I'
            else
              'M'
            end.ord.to_u8

      worksize = kind.inf? ? nrows : 0

      {% if flag?(:darwin) && T == Float32 %}
        return GMat.new(self).norm(kind)
      {% end %}

      if flags.triangular?
        lapack_util(lantr, worksize, let, uplo, 'N'.ord.to_u8, @nrows, @ncolumns, matrix(self), @nrows)
      elsif flags.hermitian?
        {% if T == Complex %}
          lapack_util(lanhe, worksize, let, uplo, @nrows, matrix(self), @nrows)
        {% else %}
          lapack_util(lange, worksize, let, @nrows, @ncolumns, matrix(self), @nrows)
        {% end %}
      elsif flags.symmetric?
        lapack_util(lansy, worksize, let, uplo, @nrows, matrix(self), @nrows)
      else
        lapack_util(lange, worksize, let, @nrows, @ncolumns, matrix(self), @nrows)
      end
    end

    def abs(kind : MatrixNorm = MatrixNorm::Frobenius)
      norm(kind)
    end

    # determine effective rank either by SVD method or QR-factorization with pivoting
    # QR method is faster, but could fail to determine rank in some cases
    def rank(eps = self.tolerance, *, method : RankMethod = RankMethod::SVD, overwrite_a = false)
      # if matrix is triangular no check needed
      return diag.count { |v| v.abs > eps } if flags.triangular?
      case method
      when .qrp?
        a, pvt = qr_r(overwrite_a: overwrite_a, pivoting: true)
        a.diag.count { |v| v.abs > eps }
      when .svd?
        s = svdvals(overwrite_a: overwrite_a)
        s.count { |x| x.abs > eps }
      end
    end
  end
end
