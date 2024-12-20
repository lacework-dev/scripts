import json
import difflib

def load_and_sort_json(file_path):
    with open(file_path, 'r') as file:
        data = json.load(file)
    return sorted(data, key=lambda x: json.dumps(x, sort_keys=True))

def main(file1, file2):
    json1 = load_and_sort_json(file1)
    json2 = load_and_sort_json(file2)

    if json1 == json2:
        print("The JSON files are identical.")
    else:
        print("The JSON files are different.")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print("Usage: python diff_json.py <file1> <file2>")
    else:
        main(sys.argv[1], sys.argv[2])
