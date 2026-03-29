Feature: Terminal navigation and ordering
  The plugin should support cycling and reordering terminal tabs.

  Scenario: Moving the current terminal right reorders the group
    Given three managed terminals exist in the current tabpage
    And the second terminal is active
    When I move the active terminal right
    Then the terminal order should place the active terminal one position later

  Scenario: Moving the current terminal left reorders the group
    Given three managed terminals exist in the current tabpage
    And the second terminal is active
    When I move the active terminal left
    Then the terminal order should place the active terminal one position earlier

  Scenario: Cycling moves between terminals
    Given three managed terminals exist in the current tabpage
    When I cycle to the next terminal
    Then the next terminal should become active

