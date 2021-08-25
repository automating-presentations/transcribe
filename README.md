# transcribe

transcribe.sh is a transcribe tool for movie or sound file.   
transcribe.sh uses Amazon S3 and Amazon Transcribe, Speech-to-Text service.

----
## Requirements

 - [AWS CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) (version 1 has not been tested.)
 - Permission to run [Amazon S3](https://aws.amazon.com/s3/) and [Amazon Transcribe](https://aws.amazon.com/transcribe/) service with AWS CLI
 - [FFmpeg](https://www.ffmpeg.org/)
 - [Python 3](https://www.python.org/)

If you use Linux or macOS(including M1 Mac), you can install AWS CLI, FFmpeg, with [Homebrew](https://brew.sh/).

```
brew install awscli ffmpeg
```
----
## How to use

The following command transcribes Japanese sound or movie file and creates "test-output.{json,txt}".  
This S3 Bucket, "testid-bucket00001", is created temporarily for the purpose of transcribe, and deleted after transcribe.

```
git clone https://github.com/automating-presentations/transcribe
chmod u+x transcribe/transcribe.sh
./transcribe/transcribe.sh -i input-ja.mp3 -bucket testid-bucket00001 -o test-output
```

The following command transcribes English sound or movie file and creates "test-output.{json,txt}".

```
./transcribe/transcribe.sh -lang en-US -i input-en.mp4 -bucket testid-bucket00001 -o test-output
```

----
## License
 - [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0)
