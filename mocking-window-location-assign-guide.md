# Mocking window.location.assign in React Applications with Jest and Jest DOM

## Overview

When testing React components that use `window.location.assign()` for navigation, you'll often encounter the error "not implemented: navigation" in Jest. This is because Jest runs in a Node.js environment with jsdom, which doesn't implement actual browser navigation. This guide covers several approaches to mock `window.location.assign` effectively.

## Method 1: Direct Mock Assignment (Simplest)

### Basic Setup

```javascript
// In your test file or setup file
beforeEach(() => {
  // Mock window.location.assign
  window.location.assign = jest.fn();
});

afterEach(() => {
  // Clean up mocks
  jest.restoreAllMocks();
});
```

### Example Test

```javascript
import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import MyComponent from './MyComponent';

// Component that uses window.location.assign
const MyComponent = () => {
  const handleRedirect = () => {
    window.location.assign('https://example.com');
  };

  return (
    <button onClick={handleRedirect}>
      Go to External Site
    </button>
  );
};

describe('MyComponent', () => {
  beforeEach(() => {
    window.location.assign = jest.fn();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('should call window.location.assign with correct URL', () => {
    render(<MyComponent />);
    
    const button = screen.getByRole('button', { name: /go to external site/i });
    fireEvent.click(button);
    
    expect(window.location.assign).toHaveBeenCalledWith('https://example.com');
    expect(window.location.assign).toHaveBeenCalledTimes(1);
  });
});
```

## Method 2: Using Object.defineProperty (More Robust)

This method is more reliable across different Jest versions and environments:

```javascript
describe('MyComponent', () => {
  let mockAssign;

  beforeEach(() => {
    mockAssign = jest.fn();
    
    // More robust way to mock window.location.assign
    Object.defineProperty(window, 'location', {
      value: {
        ...window.location,
        assign: mockAssign,
      },
      writable: true,
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('should redirect to the correct URL', () => {
    render(<MyComponent />);
    
    const button = screen.getByRole('button', { name: /go to external site/i });
    fireEvent.click(button);
    
    expect(mockAssign).toHaveBeenCalledWith('https://example.com');
  });
});
```

## Method 3: Global Setup in Jest Configuration

For projects with many tests that need this mock, set it up globally:

### jest.setup.js
```javascript
// jest.setup.js
import '@testing-library/jest-dom';

// Global mock for window.location.assign
Object.defineProperty(window, 'location', {
  value: {
    ...window.location,
    assign: jest.fn(),
    replace: jest.fn(),
    reload: jest.fn(),
  },
  writable: true,
});
```

### jest.config.js
```javascript
module.exports = {
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  testEnvironment: 'jsdom',
  // ... other config
};
```

### Using the Global Mock in Tests
```javascript
describe('MyComponent', () => {
  beforeEach(() => {
    // Clear mock calls between tests
    window.location.assign.mockClear();
  });

  it('should call window.location.assign', () => {
    render(<MyComponent />);
    
    fireEvent.click(screen.getByRole('button'));
    
    expect(window.location.assign).toHaveBeenCalledWith('https://example.com');
  });
});
```

## Method 4: Service Layer Approach (Recommended for Large Applications)

For better testability and separation of concerns, create a service layer:

### windowService.js
```javascript
// services/windowService.js
const windowService = {
  assign: (url) => {
    window.location.assign(url);
  },
  replace: (url) => {
    window.location.replace(url);
  },
  reload: () => {
    window.location.reload();
  }
};

export default windowService;
```

### Component Using Service
```javascript
import React from 'react';
import windowService from './services/windowService';

const MyComponent = () => {
  const handleRedirect = () => {
    windowService.assign('https://example.com');
  };

  return (
    <button onClick={handleRedirect}>
      Go to External Site
    </button>
  );
};

export default MyComponent;
```

### Testing with Service Mock
```javascript
import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import MyComponent from './MyComponent';
import windowService from './services/windowService';

// Mock the entire service
jest.mock('./services/windowService', () => ({
  assign: jest.fn(),
  replace: jest.fn(),
  reload: jest.fn(),
}));

describe('MyComponent', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should call windowService.assign with correct URL', () => {
    render(<MyComponent />);
    
    fireEvent.click(screen.getByRole('button'));
    
    expect(windowService.assign).toHaveBeenCalledWith('https://example.com');
    expect(windowService.assign).toHaveBeenCalledTimes(1);
  });
});
```

## Method 5: Using Custom Hook

Create a custom hook for location operations:

### useNavigation.js
```javascript
import { useCallback } from 'react';

const useNavigation = () => {
  const navigateToExternal = useCallback((url) => {
    window.location.assign(url);
  }, []);

  const replaceLocation = useCallback((url) => {
    window.location.replace(url);
  }, []);

  return {
    navigateToExternal,
    replaceLocation,
  };
};

export default useNavigation;
```

### Component Using Hook
```javascript
import React from 'react';
import useNavigation from './hooks/useNavigation';

const MyComponent = () => {
  const { navigateToExternal } = useNavigation();

  const handleRedirect = () => {
    navigateToExternal('https://example.com');
  };

  return (
    <button onClick={handleRedirect}>
      Go to External Site
    </button>
  );
};

export default MyComponent;
```

### Testing with Hook Mock
```javascript
import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import MyComponent from './MyComponent';
import useNavigation from './hooks/useNavigation';

// Mock the custom hook
jest.mock('./hooks/useNavigation');

describe('MyComponent', () => {
  const mockNavigateToExternal = jest.fn();

  beforeEach(() => {
    useNavigation.mockReturnValue({
      navigateToExternal: mockNavigateToExternal,
      replaceLocation: jest.fn(),
    });
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('should call navigateToExternal with correct URL', () => {
    render(<MyComponent />);
    
    fireEvent.click(screen.getByRole('button'));
    
    expect(mockNavigateToExternal).toHaveBeenCalledWith('https://example.com');
  });
});
```

## Testing Different Scenarios

### Testing Conditional Navigation
```javascript
describe('Conditional Navigation', () => {
  beforeEach(() => {
    window.location.assign = jest.fn();
  });

  it('should navigate only when condition is met', () => {
    const ConditionalComponent = ({ shouldNavigate }) => {
      const handleClick = () => {
        if (shouldNavigate) {
          window.location.assign('https://example.com');
        }
      };

      return <button onClick={handleClick}>Maybe Navigate</button>;
    };

    // Test when navigation should happen
    const { rerender } = render(<ConditionalComponent shouldNavigate={true} />);
    fireEvent.click(screen.getByRole('button'));
    expect(window.location.assign).toHaveBeenCalledWith('https://example.com');

    // Test when navigation should not happen
    jest.clearAllMocks();
    rerender(<ConditionalComponent shouldNavigate={false} />);
    fireEvent.click(screen.getByRole('button'));
    expect(window.location.assign).not.toHaveBeenCalled();
  });
});
```

### Testing Navigation with Dynamic URLs
```javascript
it('should navigate to dynamic URL based on user input', () => {
  const DynamicNavigationComponent = () => {
    const [url, setUrl] = React.useState('');

    const handleNavigate = () => {
      if (url) {
        window.location.assign(url);
      }
    };

    return (
      <div>
        <input 
          value={url} 
          onChange={(e) => setUrl(e.target.value)}
          placeholder="Enter URL"
        />
        <button onClick={handleNavigate}>Navigate</button>
      </div>
    );
  };

  window.location.assign = jest.fn();

  render(<DynamicNavigationComponent />);
  
  const input = screen.getByPlaceholderText('Enter URL');
  const button = screen.getByRole('button', { name: /navigate/i });
  
  fireEvent.change(input, { target: { value: 'https://dynamic-url.com' } });
  fireEvent.click(button);
  
  expect(window.location.assign).toHaveBeenCalledWith('https://dynamic-url.com');
});
```

## Common Pitfalls and Solutions

### 1. Mock Not Being Called
**Problem**: Your mock isn't being called even though the code runs.

**Solution**: Ensure the mock is set up before rendering the component:
```javascript
// ❌ Wrong - mock set up after render
render(<MyComponent />);
window.location.assign = jest.fn();

// ✅ Correct - mock set up before render
window.location.assign = jest.fn();
render(<MyComponent />);
```

### 2. Mock Persists Between Tests
**Problem**: Mock state carries over between tests.

**Solution**: Always clear mocks between tests:
```javascript
afterEach(() => {
  jest.clearAllMocks();
  // or jest.restoreAllMocks();
});
```

### 3. TypeScript Errors
**Problem**: TypeScript complains about mock assignment.

**Solution**: Type the mock properly:
```typescript
// types/jest.d.ts
declare global {
  namespace jest {
    interface MockedFunction<T extends (...args: any[]) => any>
      extends Function, MockInstance<ReturnType<T>, Parameters<T>> {}
  }
}

// In test file
(window.location.assign as jest.MockedFunction<typeof window.location.assign>) = jest.fn();
```

## Best Practices

1. **Use Service Layer**: For large applications, abstract browser APIs into services
2. **Mock Early**: Set up mocks in `beforeEach` or global setup
3. **Clear Mocks**: Always clear mocks between tests
4. **Test Edge Cases**: Test both successful navigation and error conditions
5. **Avoid Testing Implementation Details**: Focus on user-visible behavior
6. **Use Semantic Queries**: Use `getByRole`, `getByLabelText` etc. from testing-library

## Integration with React Router

If you're using React Router alongside window.location.assign for external navigation:

```javascript
import { MemoryRouter } from 'react-router-dom';

const ComponentWithRouting = () => {
  const handleExternalLink = () => {
    window.location.assign('https://external-site.com');
  };

  return (
    <div>
      <Link to="/internal">Internal Link</Link>
      <button onClick={handleExternalLink}>External Link</button>
    </div>
  );
};

// Test
it('should handle both internal and external navigation', () => {
  window.location.assign = jest.fn();
  
  render(
    <MemoryRouter>
      <ComponentWithRouting />
    </MemoryRouter>
  );
  
  // Test external navigation
  fireEvent.click(screen.getByRole('button', { name: /external link/i }));
  expect(window.location.assign).toHaveBeenCalledWith('https://external-site.com');
  
  // Test internal navigation (handled by React Router)
  fireEvent.click(screen.getByRole('link', { name: /internal link/i }));
  // Assert based on your routing logic
});
```

This comprehensive guide should help you effectively mock `window.location.assign` in your React applications using Jest and Jest DOM. Choose the method that best fits your application's architecture and testing needs.