%w[hash processctl rstatsd].each  do  |x| 
  require File.dirname(__FILE__)+"/rstatsd/#{x}" 
end

%w[oniguruma].each do |x| 
  require File.dirname(__FILE__)+"/#{x}" 
end
