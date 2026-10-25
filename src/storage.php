<?php
// File storage for capsule attachments.
//
// This is the only file that reads or writes uploaded files. They are kept in the S3 bucket
// S3_BUCKET, under the prefix "uploads/". The rest of the app only uses the three functions
// storage_save(), storage_delete() and storage_stream().
//
// There are no access keys in .env: on app-server the SDK takes temporary credentials
// from the instance role (timecapsule-dev-app-role).

function s3(): Aws\S3\S3Client
{
    static $client = null;
    return $client ??= new Aws\S3\S3Client(['region' => config('AWS_REGION', 'eu-central-1')]);
}

function s3_bucket(): string
{
    return config('S3_BUCKET') ?: throw new RuntimeException('S3_BUCKET is not set in .env.');
}

// Object key of a stored file. basename() keeps every key under "uploads/".
function s3_key(string $storedName): string
{
    return 'uploads/' . basename($storedName);
}

// Save an uploaded file ($_FILES['...'] entry) and return its stored name, e.g. "3f9a...e1.png".
// The name is random, so users cannot guess other people's file names.
function storage_save(array $uploadedFile, string $extension): string
{
    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;

    s3()->putObject([
        'Bucket' => s3_bucket(),
        'Key' => s3_key($storedName),
        'SourceFile' => $uploadedFile['tmp_name'],
        'ContentType' => mime_content_type($uploadedFile['tmp_name']) ?: 'application/octet-stream',
    ]);
    return $storedName;
}

// With versioning on, this adds a delete marker. Old versions are removed by the lifecycle rule.
function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    s3()->deleteObject(['Bucket' => s3_bucket(), 'Key' => s3_key($storedName)]);
}

// Send the browser to a presigned URL of the file. The browser downloads it from S3 directly.
// $disposition: "inline" (show in the browser) or "attachment" (download).
function storage_stream(string $storedName, string $mime, string $downloadName, string $disposition): void
{
    // Keep only safe characters for the plain filename; the UTF-8 name goes in filename*.
    $asciiName = preg_replace('/[^A-Za-z0-9._ -]/', '_', $downloadName);

    $command = s3()->getCommand('GetObject', [
        'Bucket' => s3_bucket(),
        'Key' => s3_key($storedName),
        'ResponseContentType' => $mime,
        'ResponseContentDisposition' => sprintf(
            '%s; filename="%s"; filename*=UTF-8\'\'%s',
            $disposition,
            $asciiName,
            rawurlencode($downloadName)
        ),
    ]);
    $url = (string) s3()->createPresignedRequest($command, '+5 minutes')->getUri();

    header('Location: ' . $url, true, 302);
}
