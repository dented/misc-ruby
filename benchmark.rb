require 'benchmark'

ITERATIONS = 1000000

Benchmark.bm(10) do |bench|
  0.upto(40) do |n|
    bench.report("chars: #{n}") do
      string = "n"*n
      ITERATIONS.times do
        string + 'x'
      end
    end
  end
end