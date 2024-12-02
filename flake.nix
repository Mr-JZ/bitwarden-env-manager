{
  description = "Bitwarden environment file manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Add support for common systems
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in {
    pullEnvScript = { }: ''
      if ! command -v bw >/dev/null 2>&1; then
        echo "Bitwarden CLI is not installed. Please install it first."
        exit 1
      fi

      # Check Bitwarden login status
      BW_STATUS=$(bw status | jq -r .status)
      if [ "$BW_STATUS" != "unlocked" ]; then
        echo "🔒 Bitwarden vault is locked. Please login and unlock first using:"
        echo "🔑 bw login"
        echo "🔓 bw unlock"
        exit 1
      fi

      # Get repository name and convert to uppercase
      REPO_NAME=$(basename -s .git $(git config --get remote.origin.url) | tr '[:lower:]' '[:upper:]')
      BW_ITEM_NAME="$REPO_NAME-LOCAL-ENV"

      # Check if item exists in Bitwarden
      if ! bw get item "$BW_ITEM_NAME" &>/dev/null; then
        echo "No Bitwarden entry found with name: $BW_ITEM_NAME"
        exit 1
      fi

      # Backup existing .env if it exists
      if [ -f .env ]; then
        echo "💾 Backing up existing .env to .env.backup"
        cp .env .env.backup
      fi

      # Pull the latest content from Bitwarden
      echo "Pulling latest environment variables from Bitwarden..."
      if OUTPUT=$(bw get item "$BW_ITEM_NAME" | jq -r '.notes' > .env 2>&1); then
        echo "Successfully updated .env file from Bitwarden!"
        
        if [ -f .env.backup ]; then
          echo "Checking for differences with previous version..."
          if diff .env .env.backup >/dev/null; then
            echo "✅ No changes detected."
          else
            echo "Changes detected! Review the differences:"
            diff .env.backup .env || true
          fi
        fi
      else
        echo "❌ Failed to update .env file"
        echo "Error: $OUTPUT"
        # Restore backup if it exists
        if [ -f .env.backup ]; then
          mv .env.backup .env
          echo "♻️ Restored previous .env from backup"
        fi
        exit 1
      fi

      # Clean up backup
      rm -f .env.backup
    '';

    pushEnvScript = { }: ''
      if ! command -v bw >/dev/null 2>&1; then
        echo "Bitwarden CLI is not installed. Please install it first."
        exit 1
      fi

      # Check if .env exists
      if [ ! -f .env ]; then
        echo "No .env file found in the current directory."
        exit 1
      fi

      # Check Bitwarden login status
      BW_STATUS=$(bw status | jq -r .status)
      if [ "$BW_STATUS" != "unlocked" ]; then
        echo "Bitwarden vault is locked. Please login and unlock first using:"
        echo "bw login"
        echo "bw unlock"
        exit 1
      fi

      # Get repository name and convert to uppercase
      REPO_NAME=$(basename -s .git $(git config --get remote.origin.url) | tr '[:lower:]' '[:upper:]')
      BW_ITEM_NAME="$REPO_NAME-LOCAL-ENV"

      # Check if item exists in Bitwarden
      if ! bw get item "$BW_ITEM_NAME" &>/dev/null; then
        echo "No Bitwarden entry found with name: $BW_ITEM_NAME"
        exit 1
      fi

      # Create temporary file with current Bitwarden content
      TEMP_REMOTE=$(mktemp)
      bw get item "$BW_ITEM_NAME" | jq -r '.notes' > "$TEMP_REMOTE"

      # Check for differences
      if diff -q "$TEMP_REMOTE" .env >/dev/null; then
        echo "👌 No changes detected. Skipping push to Bitwarden."
        rm -f "$TEMP_REMOTE"
        exit 0
      else
        echo "🔄 Changes detected! Here are the differences:"
        diff "$TEMP_REMOTE" .env || true
        
        echo -n "Do you want to push these changes to Bitwarden? [y/N] "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
          echo "Updating Bitwarden entry..."
          # Get the item ID first
          ITEM_ID=$(bw get item "$BW_ITEM_NAME" | jq -r '.id')
          if OUTPUT=$(bw get item "$ITEM_ID" | \
              jq --arg notes "$(cat .env)" \
              '.notes = $notes' | \
              bw encode | \
              bw edit item "$ITEM_ID" 2>&1); then
            echo "🎉 Successfully updated Bitwarden entry!"
            echo "Response from Bitwarden: $OUTPUT"
          else
            echo "Failed to update Bitwarden entry"
            echo "Error: $OUTPUT"
            rm -f "$TEMP_REMOTE"
            exit 1
          fi
        else
          echo "🚫 Push cancelled."
          rm -f "$TEMP_REMOTE"
          exit 0
        fi
      fi
      
      # Clean up
      rm -f "$TEMP_REMOTE"
    '';

    createEnvScript = { }: ''
      if ! command -v bw >/dev/null 2>&1; then
        echo "Bitwarden CLI is not installed. Please install it first."
        exit 1
      fi

      # Check if .env.example exists
      if [ ! -f .env ]; then
        echo "No .env file found in the current directory."
        exit 1
      fi

      # Check Bitwarden login status
      BW_STATUS=$(bw status | jq -r .status)
      if [ "$BW_STATUS" != "unlocked" ]; then
        echo "🔒 Bitwarden vault is locked. Please login and unlock first using:"
        echo "🧔 'bw login'"
        echo "🔓 'bw unlock'"
        exit 1
      fi

      # Get repository name and convert to uppercase
      REPO_NAME=$(basename -s .git $(git config --get remote.origin.url) | tr '[:lower:]' '[:upper:]')
      BW_ITEM_NAME="$REPO_NAME-LOCAL-ENV"

      # Check if item already exists
      if bw get item "$BW_ITEM_NAME" &>/dev/null; then
        echo "🛡️ A Bitwarden entry with name '$BW_ITEM_NAME' already exists."
        exit 1
      fi

      # Get the base template and customize it
      echo "Preparing Bitwarden entry..."
      if OUTPUT=$(bw get template item | \
          jq --arg name "$BW_ITEM_NAME" \
             --arg notes "$(cat .env)" \
          '.type=2 | .name=$name | .notes=$notes | .secureNote={"type":0}' | \
          bw encode | \
          bw create item 2>&1); then
        echo "✅ Successfully created Bitwarden entry!"
        echo "🗣️ Response from Bitwarden: $OUTPUT"
        echo "📄 You can now run 'setup-env' to fetch and create your .env file"
      else
        echo "🔴 Failed to create Bitwarden entry"
        echo "🔴 Error: $OUTPUT"
        exit 1
      fi
    '';

    setupEnvScript = { }: ''
      setup_env() {
        if ! command -v bw >/dev/null 2>&1; then
          echo "❌ Bitwarden CLI is not installed. Please install it first."
          return 1
        fi

        # Get repository name and convert to uppercase
        REPO_NAME=$(basename -s .git $(git config --get remote.origin.url) | tr '[:lower:]' '[:upper:]')
        BW_ITEM_NAME="$REPO_NAME-LOCAL-ENV"

        # Check if .env.example exists
        if [ ! -f .env.example ]; then
          echo "📛 No .env.example file found in the current directory."
          return 1
        fi

        # Check if .env already exists
        if [ -f .env ]; then
          echo "✅ .env file already exists."
          return 0
        fi

        # Check Bitwarden login status
        BW_STATUS=$(bw status | jq -r .status)
        if [ "$BW_STATUS" != "unlocked" ]; then
          echo "Bitwarden vault is locked. Please login and unlock first using:"
          echo "bw login"
          echo "bw unlock"
          return 1
        fi

        # Try to get the environment file from Bitwarden
        BW_ITEM=$(bw get item "$BW_ITEM_NAME" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
          echo "🔍 Found environment configuration in Bitwarden vault."
          echo "📝 Creating .env file from Bitwarden entry..."
          
          # Extract the notes field which contains our env file content
          bw get item "$BW_ITEM_NAME" | jq -r '.notes' > .env
          
          if [ -s .env ]; then
            echo "✨ .env file created successfully!"
            return 0
          else
            echo "Created .env file is empty. Please check the content in Bitwarden."
            rm .env
            return 1
          fi
        else
          echo "❓ No environment configuration found in Bitwarden."
          echo "📌 Please create a secure note in Bitwarden with the name: $BW_ITEM_NAME"
          echo "Copy the contents of .env.example as a starting point."
          echo "Then run this script again."
          return 1
        fi
      }

      # Run the function but don't exit the shell
      setup_env
    '';
  
        devShells = forAllSystems (system:
          let
            pkgs = pkgsFor system;
            setupScript = pkgs.writeScriptBin "setup-env" ''
              ${self.setupEnvScript {}}
            '';
            createScript = pkgs.writeScriptBin "create-env" ''
              ${self.createEnvScript {}}
            '';
            pushScript = pkgs.writeScriptBin "push-env" ''
              ${self.pushEnvScript {}}
            '';
            pullScript = pkgs.writeScriptBin "pull-env" ''
              ${self.pullEnvScript {}}
            '';
          in {
            default = pkgs.mkShell {
              buildInputs = [
                pkgs.bitwarden-cli
                pkgs.jq
                setupScript
              createScript
              pushScript
              pullScript
                            ];
                            
                            shellHook = ''
              echo "🔐 Checking Bitwarden environment setup..."
              ${self.setupEnvScript {}}
              echo "💻 Development shell ready!"
                            '';
            };
          }
        );
  };
}
