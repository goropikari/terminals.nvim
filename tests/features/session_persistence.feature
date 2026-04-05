Feature: Session Persistence
  As a Neovim user
  I want my terminal sessions to be automatically saved and restored per project
  So that I can resume my work where I left off when reopening a project

  Background:
    Given I have terminals.nvim installed with auto_restore enabled
    And I am working in a project directory "/home/user/project-alpha"

  Scenario: Save terminal state on Neovim exit
    Given I have created 3 terminals with titles "server", "tests", and "logs"
    And I have arranged them in the order: "server", "tests", "logs"
    And the "tests" terminal is currently active
    When I quit Neovim
    Then the terminal state should be saved to "~/.local/share/nvim/terminals.nvim/state_<hash>.json"
    And the saved state should include:
      | Field          | Value                                |
      | terminals      | ["server", "tests", "logs"]          |
      | active_index   | 2 (tests terminal)                   |
      | window_layout  | { position: "bottom", height: 12 }   |
      | policy         | { terminal_position: "bottom" }      |

  Scenario: Restore terminal state on Neovim start
    Given I previously saved a session with 2 terminals "dev" and "build"
    And the "build" terminal was active when saved
    When I open Neovim in the same project directory
    Then 2 terminal buffers should be recreated
    And the terminals should be restored in order: "dev", "build"
    And the "build" terminal should be set as active
    But the terminal windows should remain hidden until explicitly shown

  Scenario: Project isolation by CWD
    Given I have a session saved for "/home/user/project-alpha"
    And I have a different session saved for "/home/user/project-beta"
    When I open Neovim in "/home/user/project-alpha"
    Then only the "project-alpha" terminals should be restored
    And the "project-beta" terminals should not be affected

  Scenario: Manual save command
    Given I have created 2 terminals
    When I execute ":TerminalSave"
    Then the current terminal state should be immediately saved to disk

  Scenario: Manual restore command
    Given I have a saved session with 2 terminals
    And I have closed all current terminals
    When I execute ":TerminalRestore"
    Then the saved terminals should be restored

  Scenario: Disable auto_restore
    Given I have configured auto_restore = false
    And I have created 2 terminals
    When I quit Neovim
    Then the terminal state should NOT be saved
    And when I reopen Neovim, no terminals should be restored

  Scenario: Session persistence with Zellij backend
    Given I have configured backend = "zellij"
    And I have created 2 terminals attached to Zellij sessions
    When I quit Neovim
    Then the terminal state should be saved
    And the Zellij sessions should remain running in the background
    When I reopen Neovim
    Then the terminals should reattach to the existing Zellij sessions

  Scenario: Session persistence with Tmux backend
    Given I have configured backend = "tmux"
    And I have created 2 terminals attached to Tmux windows
    When I quit Neovim
    Then the terminal state should be saved
    And the Tmux sessions should remain running in the background
    When I reopen Neovim
    Then the terminals should reattach to the existing Tmux windows

  Scenario: Window layout restoration
    Given I have configured terminal_position = "left"
    And I have resized the terminal window to width 50
    When I quit Neovim
    And I reopen Neovim
    Then the terminal window should be restored at position "left"
    And the terminal window width should be 50

  Scenario: Clean session data
    Given I have saved session data for multiple projects
    When I execute ":TerminalClean"
    Then all in-memory state should be cleared
    And all on-disk state files should be deleted
