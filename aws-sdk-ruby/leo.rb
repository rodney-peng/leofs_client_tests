## This code supports "aws-sdk v1.9.5"
require "aws-sdk-v1"
require "content_type"

# set your s3 key and variable
Endpoint = "localhost"
Port = 8080
AccessKeyId = "05236"
SecretAccessKey = "802562235"
FileName = "testFile s"
ChunkSize = 5 * 1024 * 1024  ## 5 MB chunk size
Bucket = "test" + rand(99999).to_s  ## Dynamic BucketName
LargeObjSize = 52428800
LargeFilePath = "../temp_data/testFile.large"

class LeoFSHandler < AWS::Core::Http::NetHttpHandler
    def handle(request, response)
        request.port = ::Port
        super
    end
end

SP = AWS::Core::CredentialProviders::StaticProvider.new(
    {
        :access_key_id     => AccessKeyId,
        :secret_access_key => SecretAccessKey
    })

AWS.config(
    access_key_id: AccessKeyId,
    secret_access_key: SecretAccessKey,
    s3_endpoint: Endpoint,
    http_handler: LeoFSHandler.new,
    credential_provider: SP,
    s3_force_path_style: true,
    use_ssl: false
)

s3 = AWS::S3.new
begin
    # Create bucket
    s3.buckets.create(Bucket)
    puts "Bucket Created Successfully\n"

    # Get bucket
    bucket = s3.buckets[Bucket]
    puts "Get Bucket Successfully\n\n"

    # PUT Object
    file_path = "../temp_data/" + FileName
    fileObject =  open(file_path)

    # PUT an object using single-part method and the obj-name is "bucket-name"
    obj = bucket.objects[Bucket].write(file: file_path, content_type: fileObject.content_type)

    # PUT an object using single-part method
    obj = bucket.objects[FileName + ".single"].write(file: file_path, content_type: fileObject.content_type)

    # PUT an object using multi-part method
    puts "File is being upload:\n"
    counter = fileObject.size / ChunkSize
    uploading_object = bucket.objects[File.basename(fileObject.path)]

    uploading_object.multipart_upload(:content_type => fileObject.content_type.to_s) do |upload|
        while !fileObject.eof?
            puts " #{upload.id} \t\t #{counter} "
            counter -= 1
            upload.add_part(fileObject.read ChunkSize) ## 20MB Default size is 5242880 Byte
            p("Aborted") if upload.aborted?
        end
    end
    puts "File Uploaded Successfully\n\n"

    if !File.exist?(LargeFilePath)
        File.open(LargeFilePath, "wb") do |f|
            f.write(Random.new.bytes(LargeObjSize))
        end
    end

    # Put Single-Part Large Object
    puts "Uploading Single Part Large Object"
    largeFileObject = open(LargeFilePath)
    obj = bucket.objects[FileName + ".large.one"].write(file: LargeFilePath, content_type: largeFileObject.content_type) 

    # Put Multi-Part Large Object
    puts "Uploading Multi Part Large Object"
    largeFileObject.rewind
    uploading_object = bucket.objects[FileName + ".large.part"]
    counter = largeFileObject.size / ChunkSize
    uploading_object.multipart_upload(:content_type=> largeFileObject.content_type.to_s) do |upload|
        while !largeFileObject.eof?
            puts " #{upload.id} \t\t #{counter} "
            counter -= 1
            upload.add_part(largeFileObject.read ChunkSize)
            p("Aborted") if upload.aborted?
        end
    end

    # List objects in the bucket
    puts "----------List Files---------\n"
    bucket.objects.with_prefix("").each do |obj|
        puts obj
        if !fileObject.size.eql? obj.content_length
            if !largeFileObject.size.eql? obj.content_length
                raise " Content length is changed for : #{obj.key}"
            end
        end
        puts "#{obj.key} \t #{obj.content_length}"
    end

    # HEAD object
    fileObject.seek(0)
    fileDigest = Digest::MD5.hexdigest(fileObject.read)
    metadata = bucket.objects[FileName + ".single"].head
    puts metadata

    if !((fileObject.size.eql? metadata.content_length) && (fileDigest.eql? metadata.etag.gsub('"', ''))) ## for future use  && (fileObject.content_type.eql? metadata.content_type))
        raise "Single Part File Metadata could not match"
    else
        puts "Single Part File MetaData :"
        p metadata
    end
    metadata = bucket.objects[FileName].head
    if !(fileObject.size.eql? metadata.content_length)  ## for future use && (fileObject.content_type.eql? metadata.content_type)
        raise "Multipart File Metadata could not match"
    else
        puts "Multipart Part File MetaData :"
        p metadata
    end


    # GET object(To be handled at the below rescue block)
    if !fileObject.size.eql?  bucket.objects[FileName + ".single"].head.content_length
        raise "\nSignle part Upload File content is not equal\n"
    end
    puts "\nSingle Part Upload object data :\t" + bucket.objects[FileName + ".single"].read
    if !fileObject.size.eql? bucket.objects[FileName].head.content_length
        raise "Multi Part Upload File content is not equal\n"
    end
    if fileObject.content_type.eql? "text/plain"
        puts "Multi Part Upload object data :\t" +  bucket.objects[FileName].read + "\n"
    else
        puts "File Content type is :" + bucket.objects[FileName].content_type + "\n\n"
    end

    # GET non-existing object
    begin
        bucket.objects[FileName + ".nonexist"].read
        raise "The file must NOT be exist\n"
    rescue AWS::S3::Errors::NoSuchKey
        puts "Get non-existing object Successfully..\n"
    end

    # Range GET object
    puts "----------Range Get---------"
    resp = bucket.objects[FileName + ".single"].read(range: "bytes=1-4")
    if resp != "his "
        raise "Range Get Result does NOT match"
    else
        puts "Range Get Succeeded"
    end
    puts "\n"

    baseArr = []
    open LargeFilePath, 'r' do |f|
        f.seek 1048576
        baseArr = f.read (10485760 - 1048576 + 1)
    end

    puts "---Range Get Single-Part---"
    resp = bucket.objects[FileName + ".large.one"].read(range: "bytes=1048576-10485760")
    if resp != baseArr
        raise "Range Get Result does NOT match"
    else
        puts "Range Get Succeeded"
    end
    puts "\n"

    puts "---Range Get Multi-Part---"
    resp = bucket.objects[FileName + ".large.part"].read(range: "bytes=1048576-10485760")
    if resp != baseArr
        raise "Range Get Result does NOT match"
    else
        puts "Range Get Succeeded"
    end
    puts "\n"

    # Copy object
    bucket.objects[FileName + ".copy"].copy_from(FileName)
    if !bucket.objects[FileName + ".copy"].exists?
        raise "File could not Copy Successfully\n"
    end
    puts "File copied successfully\n"

    # List objects in the bucket
    puts "----------List Files---------\n"
    bucket.objects.with_prefix("").each do |obj|
        if !fileObject.size.eql? obj.content_length
            if !largeFileObject.size.eql? obj.content_length
                raise " Content length is changed for : #{obj.key}"
            end
        end
        puts "#{obj.key} \t #{obj.content_length}"
    end

    # Move object
    obj = bucket.objects[FileName + ".copy"].move_to(FileName + ".org")
    if !obj.exists?
        raise "File could not Moved Successfully\n"
    end
    puts "\nFile move Successfully\n"

    # List objects in the bucket
    puts "----------List Files---------\n"
    bucket.objects.with_prefix("").each do |obj|
        if !fileObject.size.eql? obj.content_length
            if !largeFileObject.size.eql? obj.content_length
                raise " Content length is changed for : #{obj.key}"
            end
        end
        puts "#{obj.key} \t #{obj.content_length}"
    end

    # Rename object
    obj = bucket.objects[FileName + ".org"].rename_to(FileName + ".copy")
    if !obj.exists?
        raise "File could not Rename Successfully\n"
    end
    puts "\nFile rename Successfully\n"

    # List objects in the bucket
    puts "----------List Files---------\n"
    bucket.objects.with_prefix("").each do |obj|
        if !fileObject.size.eql? obj.content_length
            if !largeFileObject.size.eql? obj.content_length
                raise " Content length is changed for : #{obj.key}"
            end
        end
        puts "#{obj.key} \t #{obj.content_length}"
    end

    # Download File
    File.open(FileName + ".copy", "w+") do |thisfileObject|
        bucket.objects[FileName].read do |chunk|
            thisfileObject.write(chunk)
        end
        thisfileObject.seek(0)
        thisfileDigest = Digest::MD5.hexdigest(thisfileObject.read)
        if !((thisfileObject.size.eql? metadata.content_length) && (fileDigest.eql? thisfileDigest))
            raise "Downloaded File Metadata could not match"
        else
            puts "\nFile Downloaded Successfully\n"
        end
    end

    # Delete objects one by one and check if exist
    puts "--------------------Delete Files--------------------\n"
    bucket.objects.with_prefix("").each do |obj|
        obj.delete
    end

    bucket.objects.with_prefix("").each do |obj|
        if obj.exists?
            raise "Object is not Deleted Successfully\n"
        end
        # to be not found
        begin
            obj.read
        rescue AWS::S3::Errors::NoSuchKey
            puts "#{obj.key} \t File Deleted Successfully..\n"
            next
        end
    end

    # List multi layered directories 
    # PUT an object using single-part method and the obj-name is "bucket-name"
    BaseDir = "a/b/c/"
    obj = bucket.objects[BaseDir + "test"].write(file: file_path, content_type: fileObject.content_type)
    obj2 = bucket.objects[BaseDir + "test2"].write(file: file_path, content_type: fileObject.content_type)
    bucket.objects.with_prefix(BaseDir).each do |obj|
        p obj
    end

    # Delete multi layered directories 
    BaseDir2 = "a"
    root_dir = bucket.objects[BaseDir2]
    root_dir.delete
    if root_dir.exists?
        raise "Multi layered directories are not Deleted Successfully\n"
    else
        puts "\nMulti layered directories Deleted Successfully\n"
    end

    # Delete Multiple Objects
    to_delete = []
    for fname in 1..10 do
        target = bucket.objects[BaseDir2 + fname.to_s]
        target.write(file: file_path, content_type: fileObject.content_type)
        to_delete << target
    end
    bucket.objects.delete(to_delete)
    puts "\nDelete Multiple Objects Successfully\n"

    # Get-Put ACL
    puts "\n#####Default ACL#####"
    puts "Owner ID : #{bucket.acl.owner.id}"
    puts "Owner Display name : #{bucket.acl.owner.display_name}"
    permissions = []
    bucket.acl.grants.each do |grant|
        puts "Bucket ACL is : #{grant.permission.name}"
        puts "Bucket Grantee URI is : #{grant.grantee.uri}"
        permissions << grant.permission.name
    end
    if !(permissions == [:full_control])
        raise "Permission is Not full_control"
    else
        puts "Bucket ACL permission is 'private'\n\n"
    end

    puts "#####:public_read ACL#####"
    bucket.acl = :public_read
    puts "Owner ID : #{bucket.acl.owner.id}"
    puts "Owner Display name : #{bucket.acl.owner.display_name}"
    permissions = []
    bucket.acl.grants.each do |grant|
        puts "Bucket ACL is : #{grant.permission.name}"
        puts "Bucket Grantee URI is : #{grant.grantee.uri}"
        permissions << grant.permission.name
    end
    if !(permissions == [:read, :read_acp] )
        raise "Permission is Not public_read"
    else
        puts "Bucket ACL Successfully changed to 'public-read'\n\n"
    end

    puts "#####:public_read_write ACL#####"
    bucket.acl = :public_read_write
    puts "Owner ID : #{bucket.acl.owner.id} "
    puts "Owner Display name : #{bucket.acl.owner.display_name}"
    permissions = []
    bucket.acl.grants.each do |grant|
        puts "Bucket ACL is : #{grant.permission.name}"
        puts "Bucket Grantee URI is : #{grant.grantee.uri}"
        permissions << grant.permission.name
    end
    if !(permissions == [:read, :read_acp, :write, :write_acp])
        raise "Permission is Not public_read_write"
    else
        puts "Bucket ACL Successfully changed to 'public-read-write'\n\n"
    end

    puts "#####:private ACL#####"
    bucket.acl = :private
    puts "Owner ID : #{bucket.acl.owner.id} "
    puts "Owner Display name : #{bucket.acl.owner.display_name}"
    permissions = []
    bucket.acl.grants.each do |grant|
        puts "Bucket ACL is : #{grant.permission.name}"
        puts "Bucket Grantee URI is : #{grant.grantee.uri}"
        permissions << grant.permission.name
    end
    if !(permissions == [:full_control])
        raise "Permission is Not full_control"
    else
        puts "Bucket ACL Successfully changed to 'private'\n\n"
    end
rescue
    # Unexpected error occurred
    p $!
    exit(-1)
ensure
    # Bucket Delete
#    bucket = s3.buckets[Bucket]
    #bucket.clear!  #clear the versions only
#    bucket.delete
    puts "Bucket deleted Successfully\n"
end
