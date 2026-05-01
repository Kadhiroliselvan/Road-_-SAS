import React from 'react';
import { TouchableOpacity, Text, StyleSheet, View, Animated } from 'react-native';
import { AlertTriangle } from 'lucide-react-native';

export const SOSButton = () => {
  // Simple pulse animation could be added here later

  const handleSOS = () => {
    // SOS Logic placeholder (e.g. call emergency contacts, trigger loud alarm)
    console.log("SOS TRIGGERED!");
  };

  return (
    <View style={styles.container}>
      <TouchableOpacity 
        style={styles.button} 
        activeOpacity={0.7}
        onPress={handleSOS}
      >
        <AlertTriangle color="#FFFFFF" size={28} />
        <Text style={styles.text}>SOS</Text>
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: '42%', // Sits just above the bottom panel
    right: 20,
    shadowColor: '#E63946',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 8,
    elevation: 8,
  },
  button: {
    backgroundColor: '#E63946', // Critical Red
    width: 64,
    height: 64,
    borderRadius: 32,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 4,
    borderColor: '#FEF2F2',
  },
  text: {
    color: '#FFFFFF',
    fontWeight: '800',
    fontSize: 12,
    marginTop: -2,
  }
});
