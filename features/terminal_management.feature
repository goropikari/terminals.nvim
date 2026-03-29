Feature: Terminal management
  The plugin should manage terminal buffers as tab-like entries inside a dedicated terminal window.

  Scenario: Terminal groups are isolated per tabpage
    Given a dedicated terminal window exists in the first tabpage
    When I create one terminal in the first tabpage
    And I open a second tabpage
    And I create one terminal in the second tabpage
    Then each tabpage should keep its own terminal group

  Scenario: Toggling the terminal window keeps the process alive
    Given a managed terminal is open
    When I hide the dedicated terminal window
    Then the terminal buffer should still be valid
    When I show the dedicated terminal window again
    Then the same terminal buffer should be shown again

  Scenario: Closing the last managed terminal creates a fresh terminal
    Given only one managed terminal exists in the current tabpage
    When I close the active terminal
    Then a new managed terminal should be created in the same dedicated window

  Scenario: Closing a terminal with remaining terminals switches to another one
    Given three managed terminals exist in the current tabpage
    When I close the active terminal
    Then another managed terminal should remain active

  Scenario: Only the dedicated terminal window renders the terminal winbar
    Given a managed terminal exists
    And another non-terminal window exists in the same tabpage
    Then only the dedicated terminal window should have the plugin winbar

  Scenario: Sending the current line to the active terminal
    Given an active managed terminal exists
    And a normal buffer contains a line of text
    When I send the current line to the active terminal
    Then the terminal should receive that line

  Scenario: Sending a visual selection to the active terminal
    Given an active managed terminal exists
    And a normal buffer contains a multi-line selection
    When I send the visual selection to the active terminal
    Then the terminal should receive the selected text

  Scenario: OSC title updates rename a managed terminal
    Given an active managed terminal exists
    When the terminal emits an OSC 0 or OSC 2 title sequence
    Then the managed terminal title should update
