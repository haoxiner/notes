using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public struct Trajectory
{
    public float sampleRate;
    public float timeHorizon;
    private AffineTransform[] rootTransforms;

    public Trajectory(float timeHorizon, float sampleRate, AffineTransform transform)
    {
        int halfTrajectoryLength = Mathf.FloorToInt(timeHorizon * sampleRate);
        int trajectoryLength = halfTrajectoryLength * 2;
        rootTransforms = new AffineTransform[trajectoryLength];
        for (int i = 0; i < trajectoryLength; i++)
        {
            rootTransforms[i] = transform;
        }

        this.timeHorizon = timeHorizon;
        this.sampleRate = sampleRate;
    }

    public int Length
    {
        get { return rootTransforms.Length; }
    }

    public ref AffineTransform this[int index]
    {
        get { return ref rootTransforms[index]; }
    }
}
