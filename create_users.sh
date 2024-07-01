#!/bin/bash

# Check if script is run with sudo
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run with sudo. Exiting..."
    exit 1
fi

PASSWORD_FILE_DIRECTORY="/var/secure"
PASSWORD_FILE="/var/secure/user_passwords.txt"
USERS_FILE="./users.txt"
SCRIPT_NAME="$(basename "$0")"

# Function to check if a package is installed
is_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Function to encrypt password
encrypt_password() {
    echo "$1" | openssl enc -aes-256-cbc -pbkdf2 -base64 -pass pass:"$2"
}

# Function to set Bash as default shell
set_bash_default_shell() {
    local user="$1"
    sudo chsh -s /bin/bash "$user"
}

# Check if openssl is installed
if ! is_package_installed openssl; then
    echo "openssl is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y openssl
fi

# Check if pwgen is installed
if ! is_package_installed pwgen; then
    echo "pwgen is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y pwgen
fi

# Check if the file exists
if [ ! -f "$USERS_FILE" ]; then
    echo "Error: $USERS_FILE not found."
    exit 1
fi

sudo mkdir -p "$PASSWORD_FILE_DIRECTORY"

mapfile -t lines < "$USERS_FILE"

for line in "${lines[@]}"; do
    # Remove leading and trailing whitespaces
    line=$(echo "$line" | xargs)
    
    # Split line by ';' and store the second part
    IFS=';' read -r user groups <<< "$line"
    
    # Remove leading and trailing whitespaces from the second part
    groups=$(echo "$groups" | xargs)

    IFS=',' read -ra groupsArray <<< "$groups"

    # Check if user exists
    if id "$user" &>/dev/null; then
        echo "User $user already exists. Skipping creation."
        continue
    fi

    # Generate a 6-character password using pwgen
    password=$(pwgen -sBv1 6 1)

    # Encrypt the password before storing it
    encrypted_password=$(encrypt_password "$password" "my_secret_key")

    # Store the encrypted password in the file
    echo "$user:$encrypted_password" >> "$PASSWORD_FILE"

    # Create the user with the generated password
    sudo useradd -m -p $(openssl passwd -6 "$password") "$user"

    # Set Bash as the default shell
    set_bash_default_shell "$user"

    for group in "${groupsArray[@]}"; do
        group=$(echo "$group" | xargs)
        
        # Check if group exists, if not, create it
        if ! grep -q "^$group:" /etc/group; then
            sudo groupadd "$group"
            echo "Created group $group"
        fi

        # Add user to the group
        sudo usermod -aG "$group" "$user"
        echo "Added $user to $group"
    done

    echo "User $user created with plaintext password: $password"
done

unset password

