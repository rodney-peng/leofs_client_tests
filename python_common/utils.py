def doesFileExist(s3, bucket_name, key):
    try:
        s3.do_head_object(key = key, bucket_name = bucket_name)
        return True
    except:
        return False

def doesFileMatch(io1, io2):
    while True:
        b1 = io1.read(4096)
        b2 = io2.read(4096)
        if b1 == b"":
            return b2 == b""
        elif b2 == b"":
            return b1 == b""
        elif b1 != b2:
            return False
