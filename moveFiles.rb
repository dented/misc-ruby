# /usr/ruby
class MoveFilesInDirectory

def Move(file, destination)
	File.move(file, destination) if File.exist(file) #fix this call
end

def Find(directory)
	Dir.entries.each( |f| Move(f) if File.file(f))
end

def Rename(file, newFileName)

end

def Delete(file)
end

def Search()
end

end