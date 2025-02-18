
@{
  ModuleName    = 'pastebin'
  ModuleVersion = [version]'0.1.0'
  ReleaseNotes  = '# Release Notes

- Version_0.1.0
- Functions ...
- Added a more clear usage example: Provides extensive example code demonstrating how to use each of the API methods, including creating public and unlisted pastes, logging in, listing pastes, getting user details, retrieving raw paste content (both with and without login), deleting pastes, and logging out. The examples build on each other logically.
- API Key Handling (Security): Includes a warning and suggests using a secure store (like a configuration file or environment variable) for the API key, rather than hardcoding it. This is crucial for security. Ive also added SetApiDevKey to be able to securely set the ApiKey after initial module import.
- Return Values: The methods return the API response (usually a string) on success, and $null on failure. This allows the calling code to check for errors and handle them appropriately.
- Handles "No pastes found.": Correctly interprets the "No pastes found." response as a successful (though empty) result, rather than an error.
- Handles api_results_limit: Correctly implements the api_results_limit parameter for ListPastes.
- User Key Management: Stores the api_user_key in a static property ($ApiUserKey) after a successful login. Uses this stored key for subsequent requests that require authentication. Includes a Logout() method to clear the user key.
'
}
