#!/usr/bin/env python3
"""
chat_tui.py — Interactive Streaming Terminal Chat with Real-Time TPS Speedometer for Strix Halo
"""

import sys
import json
import time
import argparse
import urllib.request

def color(text, code):
    return f"\033[{code}m{text}\033[0m"

def cyan(text): return color(text, "1;36")
def green(text): return color(text, "1;32")
def yellow(text): return color(text, "1;33")
def bold(text): return color(text, "1")
def dim(text): return color(text, "2")

def stream_chat(host, port, messages, system_prompt=None):
    url = f"http://{host}:{port}/v1/chat/completions"
    
    full_msgs = []
    if system_prompt:
        full_msgs.append({"role": "system", "content": system_prompt})
    full_msgs.extend(messages)
    
    payload = json.dumps({
        "model": "strix-model",
        "messages": full_msgs,
        "stream": True,
        "temperature": 0.7
    }).encode("utf-8")
    
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    
    start_time = time.time()
    first_token_time = None
    token_count = 0
    full_content = ""
    
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            for line in resp:
                line_str = line.decode("utf-8").strip()
                if not line_str or line_str == "data: [DONE]":
                    continue
                if line_str.startswith("data: "):
                    data_json = line_str[6:]
                    try:
                        chunk = json.loads(data_json)
                        delta = chunk.get("choices", [{}])[0].get("delta", {})
                        reasoning = delta.get("reasoning_content", "")
                        content = delta.get("content", "")
                        
                        if reasoning:
                            if first_token_time is None:
                                first_token_time = time.time()
                            token_count += 1
                            sys.stdout.write(f"\033[2m{reasoning}\033[0m")
                            sys.stdout.flush()
                        elif content:
                            if first_token_time is None:
                                first_token_time = time.time()
                            token_count += 1
                            full_content += content
                            sys.stdout.write(content)
                            sys.stdout.flush()
                    except Exception:
                        pass
                        
        total_time = time.time() - start_time
        gen_time = (total_time - (first_token_time - start_time)) if first_token_time else total_time
        tps = token_count / gen_time if gen_time > 0 else 0
        ttft_ms = ((first_token_time - start_time) * 1000) if first_token_time else 0
        
        print(f"\n{dim('-' * 70)}")
        print(f"{dim('⏱️ ')} {green(f'{tps:.1f} tok/s')} | {token_count} tokens | TTFT: {ttft_ms:.0f}ms | Total: {total_time:.2f}s")
        print(f"{dim('-' * 70)}\n")
        
        return full_content
    except Exception as e:
        print(f"\n{yellow('[Error connecting to server]')}: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Interactive Terminal Chat for Strix Halo")
    parser.add_argument("--host", default="127.0.0.1", help="Server host")
    parser.add_argument("--port", type=int, default=8000, help="Server port")
    parser.add_argument("--system", default="You are a helpful and fast AI assistant running locally on AMD Strix Halo.", help="System prompt")
    args = parser.parse_args()

    print("\n" + "=" * 70)
    print(bold(" 💬 STRIX HALO INTERACTIVE CLI CHAT"))
    print(f" Connecting to: http://{args.host}:{args.port}/v1")
    print(f" Commands: /clear (reset history), /system <prompt>, /exit (quit)")
    print("=" * 70 + "\n")

    # Check server
    try:
        urllib.request.urlopen(f"http://{args.host}:{args.port}/health", timeout=2)
    except Exception:
        print(f"{yellow('[Warning]')}: Server not responding at http://{args.host}:{args.port}.")
        print(f"Make sure to launch the server first:")
        print(f"  python3 scripts/model_manager.py run qwen38-27b --mode server --port {args.port} --mtp\n")

    history = []
    system_prompt = args.system

    while True:
        try:
            user_input = input(cyan("User > ")).strip()
            if not user_input:
                continue
                
            if user_input.lower() in ["/exit", "/quit", "exit", "quit"]:
                print("\nGoodbye!")
                break
            elif user_input.lower() == "/clear":
                history = []
                print(dim("\n[History cleared]\n"))
                continue
            elif user_input.lower().startswith("/system "):
                system_prompt = user_input[8:].strip()
                print(dim(f"\n[System prompt updated to: {system_prompt}]\n"))
                continue
            elif user_input.lower() == "/help":
                print(dim("\nAvailable commands:\n  /clear          - Reset conversation history\n  /system <text>  - Set system prompt\n  /exit           - Exit chat\n"))
                continue

            history.append({"role": "user", "content": user_input})
            sys.stdout.write(bold("\nAssistant > "))
            sys.stdout.flush()
            
            resp = stream_chat(args.host, args.port, history, system_prompt=system_prompt)
            if resp:
                history.append({"role": "assistant", "content": resp})

        except KeyboardInterrupt:
            print("\nExiting chat...")
            break

if __name__ == "__main__":
    main()
