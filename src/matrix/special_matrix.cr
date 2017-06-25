require "complex"
require "./matrix"
require "./general_matrix"

module Linalg
  module Matrix(T)
    def self.block_diag(*args)
      rows = args.sum &.rows
      columns = args.sum &.columns
      GeneralMatrix(T).new(rows, columns).tap do |result|
        row = 0
        column = 0
        args.each do |arg|
          result[row...row + arg.rows, column...column + arg.columns] = arg
          row += arg.rows
          column += arg.columns
        end
      end
    end

    def self.toeplitz(column : Indexable | Matrix, row : Indexable | Matrix | Nil = nil)
      row = row.to_a if row.is_a? Matrix
      column = column.to_a if column.is_a? Matrix
      if row
        GeneralMatrix(T).new(column.size, row.size) do |i, j|
          k = i - j
          if k >= 0
            column[k]
          else
            row[-k]
          end
        end
      else
        GeneralMatrix(T).new(column.size, column.size) do |i, j|
          k = i - j
          if k >= 0
            column[k]
          else
            column[-k].conj
          end
        end
      end
    end

    def self.circulant(c)
      GeneralMatrix(T).new(c.size, c.size) do |i, j|
        k = i - j
        c[(k + c.size) % c.size]
      end
    end
  end
end
