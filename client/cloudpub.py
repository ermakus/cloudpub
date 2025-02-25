import subprocess, threading, sys, re, time

def run_cloudpub(command):
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        shell=True, 
        bufsize=1,
    )
    
    # Variable to store the extracted URL
    extracted_url = [None]
    
    def monitor(stream_in, stream_out, extract_url=False):
        def reader():
            with stream_in:
                for line in stream_in:
                    stream_out.write(line)
                    
                    # Check for the publication message and extract URL
                    if extract_url:
                        match = re.search(r'.+ -> (.+)', line)
                        if match:
                            extracted_url[0] = match.group(1)
        return reader
            
    threading.Thread(target=monitor(process.stdout, sys.stdout, True), daemon=True).start()
    threading.Thread(target=monitor(process.stderr, sys.stderr), daemon=True).start()
    
    # Wait for the process to complete or timeout
    while True: 
        if extracted_url[0]:
            return extracted_url[0]
        time.sleep(1)

# Run the command and get the URL
url = run_cloudpub("./clo publish http 8080")
print(f"Published URL: {url}")

# Wait for key press to exit
input("Press Enter to exit...")

