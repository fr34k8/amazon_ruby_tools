#######################################
#### WRITEN by Frederico de Souza #####
#### fred.the.master@gmail.com    #####
#### Free to use as in free beer  #####
#######################################


require 'rubygems'
require 'aws/s3'
require 'fastthread'
require 'pathname'
require 'ftools'


#########################
##   SCRIPT SETTINGS   ##
#########################

@unattended_mode = true
@access_key_id = ENV['AMAZON_ACCESS_KEY_ID']
@secret_access_key = ENV['AMAZON_SECRET_ACCESS_KEY']
@bucket_name = ENV['AMAZON_BUCKET_NAME']

@time = Time.now

@data_dir = "/mnt/mysql_backups/#{@time.year}_#{@time.month}_#{@time.day}"
@filename = "#{@time.year}#{@time.month}#{@time.day}_#{@time.hour}#{@time.min}#{@time.sec}"


# Array of databases to backup
@databases = []
# If this is true, backup all databases
@all_databases = true

# Username / Password to access DB
# it's good to create a user with READ only access to all databases.
# for example: GRANT SELECT ON *.* TO 'fred'@'localhost' IDENTIFIED by 'fred'
if ENV['DB_USERNAME']
  @db_username = ENV['DB_USERNAME']
else
  @db_username = "root"
end
if ENV['DB_PASSWORD']
  @db_password = ENV['DB_PASSWORD']
else
  @db_password = ""
end

@lines = "\n----------------------------------------------------------"

if @unattended_mode == false
  puts "Welcome!"
  puts "--------"
  puts "Program Variables:"
  puts "------------------" 
  puts "- Server Username:    #{@server_username}"
  puts "- Bucket:             #{@bucket_name}"
  puts "- Local Dump Dir:     #{@data_dir}"
  puts "- Local Time of Dump: #{@time}"
  puts "- Remote Path:        #{@remote_destination}"
  puts "- Databases:          #{@databases.join(',')}"
  puts "- All Databases?      #{@all_databases}"
  puts "- DB Username:        #{@db_username}"
  puts "- DB Password:        Not Shown"
  puts "- Unattended mode:    #{@unattended_mode}"
  puts @lines
  puts "Is this Information correct?"
end

def check_directories
  begin
    FileUtils.mkdir_p(@data_dir)
  rescue
    puts "Cannot create local directory #{@data_dir}"
    exit
  end
end
  
def check_answer
  if @unattended_mode == false
    puts "Press Y to Continue or N no Cancel."
    yes_no = gets
    yes_no.chomp!
    case yes_no
      when "Y","y","Yes","yes"
        puts "Continuing"
      when "N", "n", "No", "no"
        puts "You chose to CANCEL, bye bye."
        exit
      when 'q', 'quit'
        puts "You chose to QUIT, bye bye."
        exit
      else
        puts "Invalid Answer."
        check_answer
    end
  else
    return true
  end
end

def check_settings
  if !ENV['DB_USERNAME']
    puts "WARNING: Database Username not set, using 'root'"
  end
  if !ENV['DB_PASSWORD']
    puts "WARNING: Database User Password not set, using '' (blank)"
  end
  if !ENV['AMAZON_ACCESS_KEY_ID']
    puts "FATAL: AMAZON_ACCESS_KEY_ID not set, quiting now."
    exit
  end
  if !ENV['AMAZON_SECRET_ACCESS_KEY']
    puts "FATAL: AMAZON_SECRET_ACCESS_KEY not set, quiting now."
    exit
  end  
end


# Function to make the Database Dumps
def mysqldump(db_name, file_name)
  if db_name
    if @db_password.to_s.empty?
      system(" nice mysqldump -u #{@db_username} #{db_name} > #{file_name}")
    else
      system(" nice mysqldump -u #{@db_username} -p#{@db_password} #{db_name} > #{file_name}")
    end
  else
    if @db_password.to_s.empty?
      system(" nice mysqldump -u #{@db_username} --all_databases > #{file_name}")
    else
      system(" nice mysqldump -u #{@db_username} -p#{@db_password} --all_databases > #{file_name}")
    end
  end
end

def compress_file(file_name)
  system(" nice tar -cjpf #{file_name}.tar.bz2 #{file_name}")
end

# Function to run the actual mysqldump command
def make_mysql_backup
  if @all_databases
    file_name = "#{@data_dir}/#{@filename}__ALL.sql"
    mysqldump(nil,file_name)
    puts "Compressing file #{file_name}."
    compress_file(file_name)
    puts "Deleting file #{file_name}."
    FileUtils.rm_rf(file_name)
  else
    @databases.each do |db_name|
      file_name = "#{@data_dir}/#{@filename}__#{db_name}.sql"
      puts "Dumping #{db_name} into #{file_name}\n"
      mysqldump(db_name, file_name)
      puts "Compressing file #{file_name}."
      compress_file(file_name)
      puts "Deleting file #{file_name}."
      FileUtils.rm_rf(file_name)
    end
  end
end

# Function to stablish connection
def stablish_connection
  begin
    AWS::S3::Base.establish_connection!(
      :access_key_id     => @access_key_id,
      :secret_access_key => @secret_access_key
    )
  rescue => exception
    puts @lines
    puts "There was an error: "
    puts exception.to_s
    exit
  end
  puts "Good, Connection Stablished."
end


# Function to find or create a bucket
def find_or_create_bucket
  begin
    AWS::S3::Bucket.find(@bucket_name)
  rescue
    puts "Bucket #{@bucket_name} not found."
    puts 'Creating the bucket now.'
    AWS::S3::Bucket.create(@bucket_name)
    retry
  end
  puts "Good, bucket #{@bucket_name} found."
end


# Function to send data to bucket
def send_data
  puts "Full Pathname localy is #{@data_dir}."
  @files_count = 0 
  @data_transferred = 0
  
  p = Pathname.new(@data_dir)
  p.children.each do |item|
    file_name = item.relative_path_from(Pathname.new(@data_dir)).to_s
    @files_count += 1
    @data_transferred += item.size
    puts "Putting Local File: '#{item}'"
    puts "To bucket: '#{@bucket_name}/#{file_name}'"
    AWS::S3::S3Object.store(file_name, open(item), @bucket_name)
  end

  puts @lines
  puts "Files Copied: #{@files_count}"
  puts "Data Transfered: #{to_file_size(@data_transferred)}"
  puts "done!"
end

def clean_up
  puts "Removing #{@data_dir}"
  FileUtils.rm_rf(@data_dir)
end

def to_file_size(num)
  case num
  when 0 
    return "0 byte"
  when 1..1024
    return "1K"
  when 1025..1048576
    kb = num/1024.0
    return "#{f_to_dec(kb)} Kb"
  when 1024577..1049165824
    kb = num/1024.0
    mb = kb / 1024.0
    return "#{f_to_dec(mb)} Mb"
  else
    kb = num/1024.0
    mb = kb / 1024.0
    gb = mb / 1024.0
    return "#{f_to_dec(gb)} Gb"
  end
end

def f_to_dec(f, prec=2,sep='.')
  num = f.to_i.to_s
  dig = ((prec-(post=((f*(10**prec)).to_i%(10**prec)).to_s).size).times do post='0'+post end; post)
  return num+sep+dig
end


#############
##  START  ##
#############

## Execution Start here ##
def main_program
  
  check_directories
  
  check_answer
  
  ### START MYSQL DUMP ###
  puts @lines
  puts "Starting MYSQL Dump \n"
  sleep 1
  if @all_databases 
    puts "INFO: Going to dump all databases into"
    puts "  '#{@data_dir}'"
    check_answer
  else
    puts "INFO: Going to dump '#{@databases.join(", ")}' databases into"
    puts "  '#{@data_dir}'"
  end

  # Check if destination directory at local exists
  begin
    puts "INFO: Creating Directory '#{@data_dir}' with mode 700"
    FileUtils.mkdir_p @data_dir, :mode => 0700 
  rescue
    puts "WARNING: directory '#{@data_dir}' could not be created, check your permissions."
    puts "Going to use '/tmp' folder instead."
    @data_dir = "/tmp/#{@data_dir}"
  end
  
  puts @lines
  puts "Start MYSQL dump?"
  check_answer
  make_mysql_backup
  puts "Done Dumping SQL data."
  sleep 2
  
  puts @lines
  puts "Stablishing Connection to S3 account."
  stablish_connection
  
  find_or_create_bucket
  
  puts @lines
  puts "Now Going to copy Data to S3 bucket #{@bucket_name}."
  send_data
  
  clean_up
  
  puts @lines
  puts "#{@time} -- DONE"
  puts @lines

end

main_program